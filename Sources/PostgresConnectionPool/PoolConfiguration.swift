//
//  Created by Thomas Rasch on 08.08.22.
//

import Foundation
import PostgresNIO

/// Settings for the pool like connection parameters.
public struct PoolConfiguration: Sendable {

    /// PostgreSQL connection parameters.
    @available(*, deprecated, message: "Use `PostgresConnection.Configuration` etc. instead.")
    public struct Connection {
        let username: String
        let password: String
        let host: String
        let port: Int
        let database: String

        public init(
            username: String,
            password: String,
            host: String = "localhost",
            port: Int = 5432,
            database: String)
        {
            self.username = username
            self.password = password
            self.host = host
            self.port = port
            self.database = database
        }
    }

    /// The name used for database connections and the default logger.
    public let applicationName: String

    /// Connection parameters to the database.
    public let postgresConfiguration: PostgresConnection.Configuration

    /// Timeout for opening new connections to the PostgreSQL database, in seconds (default: 5 seconds).
    public let connectTimeout: TimeInterval

    /// Time to wait before trying another connection attempt (default: 0.5 seconds).
    public let connectionRetryInterval: TimeInterval

    /// TImeout for individual database queries, in seconds (default: none).
    /// - warning: This includes the time the server needs to send the data to the client, so be careful over slow connections.
    public let queryTimeout: TimeInterval?

    /// The maximum number of open connections to the database (default: 10).
    public let poolSize: Int

    /// The maximum number of idle connections (over a 60 seconds period).
    public let maxIdleConnections: Int?

    /// Called when new connections to the database are openend.
    ///
    /// Use this to set extra connection options or override the defaults.
    public let onOpenConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)?

    /// Called before a connection is given to a client.
    ///
    /// Default is to do a quick connection check with "SELECT 1" and close the connection on errors.
    public let onReturnConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)?

    /// Called just before a connection is being closed.
    public let onCloseConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)?

    /// Pool configuation.
    ///
    /// - Parameters:
    ///   - applicationName: The name used for database connections
    ///   - postgresConfiguration: Connection parameters to the database
    ///   - connectTimeout: Timeout for opening new connections
    ///   - queryTimeout: TImeout for individual database queries
    ///   - poolSize: The maximum number of open connections
    ///   - maxIdleConnections: The maximum number of idle connections
    ///   - onOpenConnection: Called when new connections to the database are openend
    ///   - onReturnConnection: Called before a connection is given to a client
    ///   - onCloseConnection: Called just before a connection is being closed
    public init(
        applicationName: String,
        postgresConfiguration: PostgresConnection.Configuration,
        connectTimeout: TimeInterval = 5.0,
        connectionRetryInterval: TimeInterval = 0.5,
        queryTimeout: TimeInterval? = nil,
        poolSize: Int = 10,
        maxIdleConnections: Int? = nil,
        onOpenConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
        onReturnConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
        onCloseConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil)
    {
        self.applicationName = applicationName
        self.postgresConfiguration = postgresConfiguration
        self.connectTimeout = connectTimeout.atLeast(1.0)
        self.connectionRetryInterval = connectionRetryInterval.atLeast(0.0)
        self.queryTimeout = queryTimeout?.atLeast(1.0)
        self.poolSize = poolSize.atLeast(1)
        self.maxIdleConnections = maxIdleConnections?.atLeast(0)

        self.onOpenConnection = onOpenConnection
        self.onReturnConnection = onReturnConnection ?? { connection, logger in
            try await connection.query("SELECT 1", logger: logger)
        }
        self.onCloseConnection = onCloseConnection
    }

    @available(*, deprecated, message: "Use `init(applicationName:postgresConfiguration:connectTimeout:queryTimeout:poolSize:maxIdleConnections:)` instead.")
    public init(
        applicationName: String,
        connection: Connection,
        connectTimeout: TimeInterval = 5.0,
        queryTimeout: TimeInterval? = nil,
        poolSize: Int = 10,
        maxIdleConnections: Int? = nil)
    {
        let postgresConfiguration = PostgresConnection.Configuration(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: connection.password,
            database: connection.database,
            tls: .disable)
        self.init(applicationName: applicationName,
                  postgresConfiguration: postgresConfiguration,
                  connectTimeout: connectTimeout,
                  queryTimeout: queryTimeout,
                  poolSize: poolSize,
                  maxIdleConnections: maxIdleConnections)
    }

}
