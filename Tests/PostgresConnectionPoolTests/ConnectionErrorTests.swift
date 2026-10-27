//
//  Created by Thomas Rasch on 05.05.23.
//

import PostgresConnectionPool
import PostgresNIO
import Testing

@Suite("Connection Error Tests", .serialized, .enabled(if: PostgresHelpers.isAvailable))
struct ConnectionErrorTests {

    private let logger: Logger = {
        var logger = Logger(label: "ConnectionErrorTests")
        logger.logLevel = .info
        return logger
    }()

    @Test
    func `Wrong host fails with connectionError`() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(host: "notworking"), expectedErrorCode: "connectionError")
    }

    @Test
    func `Wrong port fails with connectionError`() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(port: 99999), expectedErrorCode: "connectionError")
    }

    @Test
    func `Wrong username fails with password auth error`() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(username: "notworking")) { error in
            #expect(error.pgPoolDescription == "<PSQLError (code 28P01): FATAL: password authentication failed for user \"notworking\">")
        }
    }

    @Test
    func `Wrong password fails with password auth error`() async throws {
        try await withConfiguration(PostgresHelpers.poolConfiguration(password: "notworking")) { error in
            #expect(error.pgPoolDescription == "<PSQLError (code 28P01): FATAL: password authentication failed for user \"test_username\">")
        }
    }

    @Test
    func `Invalid TLS config fails cleanly`() async throws {
        var tlsConfiguration: TLSConfiguration = .clientDefault
        tlsConfiguration.maximumTLSVersion = .tlsv1

        let tls: PostgresConnection.Configuration.TLS = try .require(.init(configuration: tlsConfiguration))
        try await withConfiguration(PostgresHelpers.poolConfiguration(tls: tls)) { error in
            let description = error.pgPoolDescription
            #expect(
                description.hasPrefix("<PSQLError: sslUnsupported")
                    || description.contains("handshakeFailed")
                    || description.contains("TLS"),
            )
            #expect(error.pgPoolDebugDescription.contains("underlying:"))
        }
    }

    // MARK: -

    private func withConfiguration(
        _ configuration: PoolConfiguration,
        expectedErrorCode: String,
    ) async throws {
        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            await pool.shutdown()

            Issue.record("Can't connect, so we should have an error here")
        }
        catch {
            guard case PoolError.poolDestroyed = error else {
                Issue.record("Expected PoolError.poolDestroyed, got \(error)")
                return
            }

            let shutdownError = await pool.shutdownError
            let errorDescription = shutdownError?.pgPoolDescription ?? ""
            let debugDescription = shutdownError?.pgPoolDebugDescription ?? ""
            #expect(errorDescription.hasPrefix("<PSQLError: \(expectedErrorCode)"))
            #expect(debugDescription.contains("underlying:"))
        }

        let didShutdown = await pool.isShutdown
        #expect(didShutdown)
    }

    private func withConfiguration(
        _ configuration: PoolConfiguration,
        verify: (PSQLError) -> Void,
    ) async throws {
        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            await pool.shutdown()

            Issue.record("Can't connect, so we should have an error here")
        }
        catch {
            guard case PoolError.poolDestroyed = error else {
                Issue.record("Expected PoolError.poolDestroyed, got \(error)")
                return
            }

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
