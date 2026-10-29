//
//  Created by Thomas Rasch on 24.04.23.
//

import Atomics
import Foundation
import PostgresKit
import PostgresNIO

/// A thread-safe handle to a pooled PostgreSQL connection.
///
/// ``PostgresConnectionWrapper`` is received inside the callback passed to
/// ``PostgresConnectionPool/connection(batchId:_:)``. It forwards query
/// execution and listen/notify operations to the underlying `PostgresConnection`
/// while tracking query runtimes for diagnostics.
///
/// The wrapper is only valid for the duration of the callback. Do not store it,
/// return it, or let a query sequence or `SQLDatabase` escape the callback: the
/// underlying connection is returned to the pool as soon as the callback
/// returns and may then be used by another caller.
public final class PostgresConnectionWrapper: Sendable {

    private let poolConnection: PoolConnection
    private let postgresConnection: PostgresConnection
    private let valid = ManagedAtomic<Bool>(true)

    static func distribute<T>(
        poolConnection: PoolConnection?,
        callback: (PostgresConnectionWrapper) async throws -> T
    ) async throws -> T {
        guard let poolConnection,
              let connectionWrapper = PostgresConnectionWrapper(poolConnection)
        else { throw PoolError.unknown }

        connectionWrapper.poolConnection.query = nil
        defer {
            connectionWrapper.invalidate()
            connectionWrapper.poolConnection.query = nil
        }

        do {
            return try await callback(connectionWrapper)
        }
        catch let error as PSQLError {
            guard let serverInfo = error.serverInfo,
                  let code = serverInfo[.sqlState]
            else { throw error }

            switch PostgresError.Code(raw: code) {
            case .queryCanceled:
                throw PoolError.queryCancelled(
                    query: connectionWrapper.poolConnection.query ?? "<unknown>",
                    runtime: connectionWrapper.poolConnection.queryRuntime ?? 0.0)

            default:
                throw PoolError.postgresError(error)
            }
        }
        catch {
            throw error
        }
    }

    init?(_ poolConnection: PoolConnection) {
        guard let postgresConnection = poolConnection.connection else { return nil }

        self.poolConnection = poolConnection
        self.postgresConnection = postgresConnection
    }

    private func invalidate() {
        valid.store(false, ordering: .releasing)
    }

    // MARK: - Public interface, from PostgresConnection

    /// Whether this handle is still valid.
    ///
    /// The handle becomes invalid as soon as the connection callback returns.
    public var isValid: Bool {
        valid.load(ordering: .acquiring)
    }

    /// The database logger associated with this connection.
    public var logger: Logger {
        postgresConnection.logger
    }

    /// Whether the underlying Postgres connection has been closed.
    public var isClosed: Bool {
        postgresConnection.isClosed
    }

    /// Executes a query on the PostgreSQL server.
    ///
    /// The query text is tracked for diagnostic purposes and can be inspected via
    /// ``PoolInfo/ConnectionInfo/query`` and ``PoolInfo/ConnectionInfo/queryRuntime``.
    ///
    /// - Parameters:
    ///   - query: The `PostgresQuery` to execute.
    ///   - logger: The logger to use for query-level logging.
    ///   - file: Source file of the call site (for error reporting).
    ///   - line: Source line of the call site (for error reporting).
    /// - Returns: A `PostgresRowSequence` containing the result rows. The
    ///   sequence must be fully consumed before the connection callback returns.
    @discardableResult
    public func query(
        _ query: PostgresQuery,
        logger: Logger,
        file: String = #fileID,
        line: Int = #line
    ) async throws -> PostgresRowSequence {
        guard isValid, !postgresConnection.isClosed else {
            throw PoolError.connectionFailed
        }

        poolConnection.query = query.sql
        return try await postgresConnection.query(query, logger: logger, file: file, line: line)
    }

    /// Returns a `SQLDatabase`-conforming wrapper for use with PostgresKit.
    ///
    /// - Parameters:
    ///   - encodingContext: The JSON encoding context.
    ///   - decodingContext: The JSON decoding context.
    ///   - queryLogLevel: The log level for query logging.
    /// - Returns: A `SQLDatabase` for executing queries via PostgresKit. The
    ///   returned database must not escape the connection callback.
    public func sql(
        encodingContext: PostgresEncodingContext<some PostgresJSONEncoder> = .default,
        decodingContext: PostgresDecodingContext<some PostgresJSONDecoder> = .default,
        queryLogLevel: Logger.Level? = .debug
    ) -> some SQLDatabase {
        precondition(isValid, "PostgresConnectionWrapper used after its connection callback returned")

        return postgresConnection.sql(encodingContext: encodingContext, decodingContext: decodingContext, queryLogLevel: queryLogLevel)
    }

    /// Registers a handler for `NOTIFY` messages on a channel.
    ///
    /// Use this in conjunction with PostgreSQL's `LISTEN`/`NOTIFY` support.
    /// After adding a listener, issue a `LISTEN` query to begin receiving notifications.
    /// Stop the listener before the connection callback returns.
    ///
    /// - Parameters:
    ///   - channel: The channel name to listen on.
    ///   - notificationHandler: A closure invoked when a notification is received.
    /// - Returns: A `PostgresListenContext` that can be used to stop listening.
    @discardableResult
    public func addListener(
        channel: String,
        handler notificationHandler: @Sendable @escaping (PostgresListenContext, PostgresMessage.NotificationResponse) -> Void
    ) -> PostgresListenContext {
        precondition(isValid, "PostgresConnectionWrapper used after its connection callback returned")

        poolConnection.query = "LISTEN \(channel)"
        return postgresConnection.addListener(channel: channel, handler: notificationHandler)
    }

    /// Start listening for a channel.
    ///
    /// The notification sequence must not escape the connection callback.
    ///
    /// - Parameter channel: The channel name to listen on.
    /// - Returns: An async sequence of `PostgresMessage.NotificationResponse` events.
    public func listen(
        _ channel: String
    ) async throws -> PostgresNotificationSequence {
        guard isValid else { throw PoolError.connectionFailed }

        poolConnection.query = "LISTEN \(channel)"
        return try await postgresConnection.listen(on: channel) { $0 }
    }

    /// Listen on a channel and consume notifications via the given closure.
    ///
    /// The closure must finish before the connection callback returns.
    ///
    /// - Parameters:
    ///   - channel: The channel name to listen on.
    ///   - consume: A closure that receives the notification sequence and processes it.
    /// - Returns: The value returned by the consume closure.
    @discardableResult
    public func listen<Value>(
        on channel: String,
        consume: (PostgresNotificationSequence) async throws -> Value
    ) async throws -> Value {
        guard isValid else { throw PoolError.connectionFailed }

        poolConnection.query = "LISTEN \(channel)"
        return try await postgresConnection.listen(on: channel, consume: consume)
    }

}
