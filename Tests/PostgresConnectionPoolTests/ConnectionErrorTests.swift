//
//  Created by Thomas Rasch on 05.05.23.
//

import PostgresConnectionPool
import PostgresNIO
import XCTest

final class ConnectionErrorTests: XCTestCase {

    private var logger: Logger = {
        var logger = Logger(label: "ConnectionErrorTests")
        logger.logLevel = .info
        return logger
    }()

    // TODO: Clean up the error checking
    // TODO: Check that the Docker PostgreSQL server is actually up and available first or most tests will fail anyway

    private func withConfiguration(
        _ configuration: PoolConfiguration,
        expectedErrorDescription: String)
        async throws
    {
        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)
        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            await pool.shutdown()

            XCTFail("Can't connect, so we should have an exception")
        }
        catch {
            XCTAssertTrue(error is PoolError)

            let shutdownError = await pool.shutdownError
            XCTAssertEqual(shutdownError?.description, expectedErrorDescription)
        }
        let didShutdown = await pool.didShutdown
        XCTAssertTrue(didShutdown)
    }

    func testConnectWrongHost() async throws {
        try await withConfiguration(self.poolConfiguration(host: "notworking"), expectedErrorDescription: "<PoolError: postgresError=<PSQLError: connectionError>>")
    }

    func testConnectWrongPort() async throws {
        try await withConfiguration(self.poolConfiguration(port: 99999), expectedErrorDescription: "<PoolError: postgresError=<PSQLError: connectionError>>")
    }

    func testConnectWrongUsername() async throws {
        try await withConfiguration(self.poolConfiguration(username: "notworking"), expectedErrorDescription: "<PoolError: postgresError=<PSQLError: FATAL: password authentication failed for user \"notworking\">>")
    }

    func testConnectWrongPassword() async throws {
        try await withConfiguration(self.poolConfiguration(password: "notworking"), expectedErrorDescription: "<PoolError: postgresError=<PSQLError: FATAL: password authentication failed for user \"test_username\">>")
    }

    func testConnectInvalidTLSConfig() async throws {
        var tlsConfiguration: TLSConfiguration = .clientDefault
        tlsConfiguration.maximumTLSVersion = .tlsv1 // New Postgres versions want at least TLSv1.2

        let tls: PostgresConnection.Configuration.TLS = .require(try .init(configuration: tlsConfiguration))
        try await withConfiguration(self.poolConfiguration(tls: tls), expectedErrorDescription: "<PoolError: postgresError=<PSQLError: sslUnsupported>>")
    }

    // MARK: -

    private func poolConfiguration(
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        database: String? = nil,
        tls: PostgresConnection.Configuration.TLS = .disable)
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
            applicationName: "ConnectionErrorTests",
            postgresConfiguration: postgresConfiguration,
            connectTimeout: 10.0,
            queryTimeout: 10.0,
            poolSize: 5,
            maxIdleConnections: 1)
    }

    private func env(_ name: String) -> String? {
        getenv(name).flatMap { String(cString: $0) }
    }
}
