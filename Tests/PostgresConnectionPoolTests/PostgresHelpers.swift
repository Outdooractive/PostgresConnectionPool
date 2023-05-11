//
//  Created by Thomas Rasch on 11.05.23.
//

import Foundation
import PostgresConnectionPool
import PostgresNIO

enum PostgresHelpers {

    static func poolConfiguration(
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        database: String? = nil,
        tls: PostgresConnection.Configuration.TLS = .disable,
        poolSize: Int = 5)
        -> PoolConfiguration
    {
        let postgresConfiguration = PostgresConnection.Configuration(
            host: host ?? env("POSTGRES_HOSTNAME") ?? "localhost",
            port: port ?? env("POSTGRES_PORT").flatMap(Int.init(_:)) ?? 5432,
            username: username ?? env("POSTGRES_USER") ?? "test_username",
            password: password ?? env("POSTGRES_PASSWORD") ?? "test_password",
            database: database ?? env("POSTGRES_DB") ?? "test_database",
            tls: tls)
        return PoolConfiguration(
            applicationName: "PoolTests",
            postgresConfiguration: postgresConfiguration,
            connectTimeout: 10.0,
            queryTimeout: 10.0,
            poolSize: poolSize,
            maxIdleConnections: 1)
    }

    private static func env(_ name: String) -> String? {
        getenv(name).flatMap { String(cString: $0) }
    }

}
