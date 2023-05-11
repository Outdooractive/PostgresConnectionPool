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

    // MARK: -

    // TODO: Clean up the error checking
    // TODO: Check that the Docker PostgreSQL server is actually up and available first or most tests will fail anyway

    func testConnectWrongHost() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(host: "notworking"), expectedErrorDescription: "<PSQLError: connectionError>")
    }

    func testConnectWrongPort() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(port: 99999), expectedErrorDescription: "<PSQLError: connectionError>")
    }

    func testConnectWrongUsername() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(username: "notworking"), expectedErrorDescription: "<PSQLError: FATAL: password authentication failed for user \"notworking\">")
    }

    func testConnectWrongPassword() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(password: "notworking"), expectedErrorDescription: "<PSQLError: FATAL: password authentication failed for user \"test_username\">")
    }

    func testConnectInvalidTLSConfig() async throws {
        var tlsConfiguration: TLSConfiguration = .clientDefault
        tlsConfiguration.maximumTLSVersion = .tlsv1 // New Postgres versions want at least TLSv1.2

        let tls: PostgresConnection.Configuration.TLS = .require(try .init(configuration: tlsConfiguration))
        try await withConfiguration(PostgresHelpers.poolConfiguration(tls: tls), expectedErrorDescription: "<PSQLError: sslUnsupported>")
    }

    // MARK: -

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

            XCTFail("Can't connect, so we should have an exception here")
        }
        catch {
            XCTAssertTrue(error is PoolError)

            let shutdownError = await pool.shutdownError
            XCTAssertEqual(shutdownError?.description, expectedErrorDescription)
        }

        let didShutdown = await pool.isShutdown
        XCTAssertTrue(didShutdown)
    }

}
