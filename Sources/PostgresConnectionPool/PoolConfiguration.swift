//
//  Created by Thomas Rasch on 08.08.22.
//

import Foundation
import PostgresNIO

/// Settings for the pool like connection parameters.
public struct PoolConfiguration {

    /// PostgreSQL connection parameters.
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
    public let connection: Connection

    /// Timeout for opening new connections to the PostgreSQL database, in seconds (default: 5 seconds).
    public let connectTimeout: TimeInterval

    /// TImeout for individual database queries, in seconds (default: 10 seconds).
    /// Can be disabled by setting to `nil`.
    public let queryTimeout: TimeInterval?

    /// The maximum number of open connections to the database (default: 10).
    public let poolSize: Int

    /// The maximum number of idle connections (over a 60 seconds period).
    public let maxIdleConnections: Int?

    /// Called when new connections to the database are openend.
    ///
    /// Use this to set extra connection options or override the defaults.
    public var onOpenConnection: ((PostgresConnection, Logger) async throws -> Void)?

    /// Called before a connection is given to a client.
    ///
    /// Default is to do a quick connection check with "SELECT 1" and close the connection on errors.
    public var onReturnConnection: ((PostgresConnection, Logger) async throws -> Void)?

    /// Called just before a connection is being closed.
    public var onCloseConnection: ((PostgresConnection, Logger) async throws -> Void)?

    public init(
        applicationName: String,
        connection: Connection,
        connectTimeout: TimeInterval = 5.0,
        queryTimeout: TimeInterval? = 10.0,
        poolSize: Int = 10,
        maxIdleConnections: Int? = nil)
    {
        self.applicationName = applicationName
        self.connection = connection
        self.connectTimeout = connectTimeout.atLeast(1.0)
        self.queryTimeout = queryTimeout?.atLeast(1.0)
        self.poolSize = poolSize.atLeast(1)
        self.maxIdleConnections = maxIdleConnections?.atLeast(0)

        self.onReturnConnection = { connection, logger in
            try await connection.query("SELECT 1", logger: logger)
        }
    }

}
