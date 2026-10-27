//
//  Created by Thomas Rasch on 08.08.22.
//

import Foundation
import PostgresNIO

/// Settings for the connection pool.
public struct PoolConfiguration: Sendable {

    /// The name used for database connections and the default logger.
    public let applicationName: String

    /// Connection parameters to the database.
    public let postgresConfiguration: PostgresConnection.Configuration

    /// Timeout for opening new connections (default: 5 seconds).
    public let connectTimeout: TimeInterval

    /// Time to wait before retrying a failed connection attempt (default: 0.5 seconds).
    public let connectionRetryInterval: TimeInterval

    /// Timeout for individual database queries. `nil` means no timeout.
    ///
    /// This includes the time the server needs to send the data to the client,
    /// so use a generous value over slow connections.
    public let queryTimeout: TimeInterval?

    /// The maximum number of open connections to the database (default: 10).
    public let poolSize: Int

    /// The maximum number of idle connections to keep open over a 60-second window.
    public let maxIdleConnections: Int?

    /// Whether the built-in default `SELECT 1` health check is installed.
    ///
    /// Defaults to `true`. This only affects the fallback used when no custom
    /// ``onReturnConnection`` is provided; a custom callback is always honored.
    /// Disable the default when the extra round trip per lease is not worth the
    /// protection against handing out a dead idle connection.
    public let defaultHealthCheckEnabled: Bool

    /// Called when new connections to the database are opened.
    ///
    /// Use this to set extra connection options or override the defaults.
    public let onOpenConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)?

    /// Called before a connection is given to a client.
    ///
    /// A custom callback is always used, regardless of
    /// ``defaultHealthCheckEnabled``. When this is `nil` and
    /// ``defaultHealthCheckEnabled`` is `true`, the built-in default runs
    /// `SELECT 1` as a health check.
    public let onReturnConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)?

    /// Called just before a connection is closed.
    public let onCloseConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)?

    /// Creates a pool configuration.
    ///
    /// - Parameters:
    ///   - applicationName: The name used for database connections and the default logger.
    ///   - postgresConfiguration: Connection parameters to the database.
    ///   - connectTimeout: Timeout for opening new connections (default: 5 seconds).
    ///   - connectionRetryInterval: Time to wait before retrying a failed connection attempt (default: 0.5 seconds).
    ///   - queryTimeout: Timeout for individual database queries. `nil` means no timeout.
    ///   - poolSize: The maximum number of open connections (default: 10).
    ///   - maxIdleConnections: The maximum number of idle connections to keep open.
    ///   - defaultHealthCheckEnabled: Whether to install the default `SELECT 1` health check when no custom
    ///     ``onReturnConnection`` is provided.
    ///   - onOpenConnection: Called when new connections are opened.
    ///   - onReturnConnection: Called before a connection is returned to a caller. A custom callback is
    ///     always used, even when the default health check is disabled.
    ///   - onCloseConnection: Called just before a connection is closed.
    public init(
        applicationName: String,
        postgresConfiguration: PostgresConnection.Configuration,
        connectTimeout: TimeInterval = 5.0,
        connectionRetryInterval: TimeInterval = 0.5,
        queryTimeout: TimeInterval? = nil,
        poolSize: Int = 10,
        maxIdleConnections: Int? = nil,
        defaultHealthCheckEnabled: Bool = true,
        onOpenConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
        onReturnConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
        onCloseConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
    ) {
        self.applicationName = applicationName
        self.postgresConfiguration = postgresConfiguration
        self.connectTimeout = connectTimeout.atLeast(1.0)
        self.connectionRetryInterval = connectionRetryInterval.atLeast(0.0)
        self.queryTimeout = queryTimeout?.atLeast(1.0)
        self.poolSize = poolSize.atLeast(1)
        self.maxIdleConnections = maxIdleConnections?.atLeast(0)
        self.defaultHealthCheckEnabled = defaultHealthCheckEnabled

        self.onOpenConnection = onOpenConnection

        if let onReturnConnection {
            self.onReturnConnection = onReturnConnection
        }
        else if defaultHealthCheckEnabled {
            self.onReturnConnection = { connection, logger in
                try await connection.query("SELECT 1", logger: logger)
            }
        }
        else {
            self.onReturnConnection = nil
        }

        self.onCloseConnection = onCloseConnection
    }

}
