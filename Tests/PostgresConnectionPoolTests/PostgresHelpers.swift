//
//  Created by Thomas Rasch on 11.05.23.
//

import Foundation
import PostgresConnectionPool
import PostgresNIO

enum PostgresHelpers {

    /// Whether the integration tests should run.
    ///
    /// Set `POSTGRES_HOSTNAME` to point at a database, or `POSTGRES_TESTS=1`
    /// for a local database on the default host.
    static var isAvailable: Bool {
        env("POSTGRES_HOSTNAME") != nil || env("POSTGRES_TESTS") == "1"
    }

    static func poolConfiguration(
        applicationName: String = "PoolTests",
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        database: String? = nil,
        tls: PostgresConnection.Configuration.TLS = .disable,
        connectTimeout: TimeInterval = 10.0,
        connectionRetryInterval: TimeInterval = 0.5,
        queryTimeout: TimeInterval? = 10.0,
        poolSize: Int = 5,
        maxIdleConnections: Int? = 1,
        defaultHealthCheckEnabled: Bool = true,
        onOpenConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
        onReturnConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
        onCloseConnection: (@Sendable (PostgresConnection, Logger) async throws -> Void)? = nil,
    ) -> PoolConfiguration {
        let postgresConfiguration = PostgresConnection.Configuration(
            host: host ?? env("POSTGRES_HOSTNAME") ?? "localhost",
            port: port ?? env("POSTGRES_PORT").flatMap(Int.init(_:)) ?? 5432,
            username: username ?? env("POSTGRES_USER") ?? "test_username",
            password: password ?? env("POSTGRES_PASSWORD") ?? "test_password",
            database: database ?? env("POSTGRES_DB") ?? "test_database",
            tls: tls)
        return PoolConfiguration(
            applicationName: applicationName,
            postgresConfiguration: postgresConfiguration,
            connectTimeout: connectTimeout,
            connectionRetryInterval: connectionRetryInterval,
            queryTimeout: queryTimeout,
            poolSize: poolSize,
            maxIdleConnections: maxIdleConnections,
            defaultHealthCheckEnabled: defaultHealthCheckEnabled,
            onOpenConnection: onOpenConnection,
            onReturnConnection: onReturnConnection,
            onCloseConnection: onCloseConnection)
    }

    static func postgresClientConfiguration(
        maximumConnections: Int = 2,
        additionalStartupParameters: [(String, String)] = [],
    ) -> PostgresClient.Configuration {
        var configuration = PostgresClient.Configuration(
            host: env("POSTGRES_HOSTNAME") ?? "localhost",
            port: env("POSTGRES_PORT").flatMap(Int.init(_:)) ?? 5432,
            username: env("POSTGRES_USER") ?? "test_username",
            password: env("POSTGRES_PASSWORD") ?? "test_password",
            database: env("POSTGRES_DB") ?? "test_database",
            tls: .disable)
        configuration.options.minimumConnections = 0
        configuration.options.maximumConnections = maximumConnections
        configuration.options.keepAliveBehavior = nil
        configuration.options.connectionIdleTimeout = .seconds(1)
        configuration.options.additionalStartupParameters = additionalStartupParameters
        return configuration
    }

    private static func env(_ name: String) -> String? {
        getenv(name).flatMap { String(cString: $0) }
    }

}
