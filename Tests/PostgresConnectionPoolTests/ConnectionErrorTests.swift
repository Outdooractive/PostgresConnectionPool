//
//  Created by Thomas Rasch on 05.05.23.
//

import PostgresConnectionPool
import PostgresNIO
import Testing

@Suite("Connection Error Tests", .serialized)
struct ConnectionErrorTests {

    private let logger: Logger = {
        var logger = Logger(label: "ConnectionErrorTests")
        logger.logLevel = .info
        return logger
    }()

    @Test("Wrong host fails with connectionError")
    func testConnectWrongHost() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(host: "notworking"), expectedErrorCode: "connectionError")
    }

    @Test("Wrong port fails with connectionError")
    func testConnectWrongPort() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(port: 99999), expectedErrorCode: "connectionError")
    }

    @Test("Wrong username fails with password auth error")
    func testConnectWrongUsername() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(username: "notworking")) { error in
            #expect(error.pgPoolDescription == "<PSQLError (code 28P01): FATAL: password authentication failed for user \"notworking\">")
        }
    }

    @Test("Wrong password fails with password auth error")
    func testConnectWrongPassword() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(password: "notworking")) { error in
            #expect(error.pgPoolDescription == "<PSQLError (code 28P01): FATAL: password authentication failed for user \"test_username\">")
        }
    }

    @Test("Invalid TLS config fails with sslUnsupported")
    func testConnectInvalidTLSConfig() async throws {
        var tlsConfiguration: TLSConfiguration = .clientDefault
        tlsConfiguration.maximumTLSVersion = .tlsv1

        let tls: PostgresConnection.Configuration.TLS = .require(try .init(configuration: tlsConfiguration))
        try await withConfiguration(PostgresHelpers.poolConfiguration(tls: tls)) { error in
            #expect(error.pgPoolDescription == "<PSQLError: sslUnsupported>")
        }
    }

    // MARK: -

    private func withConfiguration(
        _ configuration: PoolConfiguration,
        expectedErrorCode: String)
        async throws
    {
        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            await pool.shutdown()

            Issue.record("Can't connect, so we should have an error here")
        }
        catch {
            #expect(error is PoolError)

            let shutdownError = await pool.shutdownError
            let errorDescription = shutdownError?.pgPoolDescription ?? ""
            #expect(errorDescription.hasPrefix("<PSQLError: \(expectedErrorCode)"))
        }

        let didShutdown = await pool.isShutdown
        #expect(didShutdown)
    }

    private func withConfiguration(
        _ configuration: PoolConfiguration,
        verify: (PSQLError) -> Void)
        async throws
    {
        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            await pool.shutdown()

            Issue.record("Can't connect, so we should have an error here")
        }
        catch {
            #expect(error is PoolError)

            if let shutdownError = await pool.shutdownError {
                verify(shutdownError)
            }
            else {
                Issue.record("Expected shutdownError to be set")
            }
        }

        let didShutdown = await pool.isShutdown
        #expect(didShutdown)
    }

}
