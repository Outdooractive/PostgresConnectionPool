//
//  Created by Thomas Rasch on 08.08.22.
//

import Foundation

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

    /// Timeout for opening new connections to the PostgreSQL database, in seconds.
    public let connectTimeout: TimeInterval

    /// TImeout for individual database queries, in seconds.
    public let queryTimeout: TimeInterval

    /// The pool size.
    public let poolSize: Int

    public init(
        applicationName: String,
        connection: Connection,
        connectTimeout: TimeInterval = 5.0,
        queryTimeout: TimeInterval = 10.0,
        poolSize: Int = 10)
    {
        self.applicationName = applicationName
        self.connection = connection
        self.connectTimeout = connectTimeout.atLeast(1.0)
        self.queryTimeout = queryTimeout.atLeast(1.0)
        self.poolSize = poolSize.atLeast(1)
    }

}
