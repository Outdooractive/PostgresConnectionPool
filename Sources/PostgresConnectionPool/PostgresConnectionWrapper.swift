//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation
import PostgresKit
import PostgresNIO

public final class PostgresConnectionWrapper {

    private let poolConnection: PoolConnection
    private let postgresConnection: PostgresConnection

    static func distribute<T>(
        poolConnection: PoolConnection?,
        callback: (PostgresConnectionWrapper) async throws -> T)
        async throws -> T
    {
        guard let poolConnection,
              let connectionWrapper = PostgresConnectionWrapper(poolConnection)
        else { throw PoolError.unknown }

        connectionWrapper.poolConnection.query = nil
        defer {
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
                throw PoolError.queryCancelled
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

    // MARK: - Public interface, from PostgresConnection

    /// A logger to use in case
    public var logger: Logger {
        postgresConnection.logger
    }

    public var isClosed: Bool {
        postgresConnection.isClosed
    }

    /// Run a query on the Postgres server the connection is connected to.
    ///
    /// - Parameters:
    ///   - query: The ``PostgresQuery`` to run
    ///   - logger: The `Logger` to log into for the query
    ///   - file: The file, the query was started in. Used for better error reporting.
    ///   - line: The line, the query was started in. Used for better error reporting.
    /// - Returns: A ``PostgresRowSequence`` containing the rows the server sent as the query result.
    ///            The sequence can  be discarded.
    @discardableResult
    public func query(
        _ query: PostgresQuery,
        logger: Logger,
        file: String = #fileID,
        line: Int = #line)
        async throws -> PostgresRowSequence
    {
        poolConnection.query = query.sql
        return try await postgresConnection.query(query, logger: logger, file: file, line: line)
    }

    public func sql(
        encoder: PostgresDataEncoder = PostgresDataEncoder(),
        decoder: PostgresDataDecoder = PostgresDataDecoder())
        -> SQLDatabase
    {
        postgresConnection.sql(encoder: encoder, decoder: decoder)
    }

    /// Add a handler for NotificationResponse messages on a certain channel. This is used in conjunction with PostgreSQL's `LISTEN`/`NOTIFY` support: to listen on a channel, you add a listener using this method to handle the NotificationResponse messages, then issue a `LISTEN` query to instruct PostgreSQL to begin sending NotificationResponse messages.
    @discardableResult
    public func addListener(
        channel: String,
        handler notificationHandler: @escaping (PostgresListenContext, PostgresMessage.NotificationResponse) -> Void)
        -> PostgresListenContext
    {
        postgresConnection.addListener(channel: channel, handler: notificationHandler)
    }

}
