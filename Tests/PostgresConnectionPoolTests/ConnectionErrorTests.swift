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
    func `Wrong host fails transiently and keeps the pool alive`() async throws {
        try await withTransientConfiguration(PostgresHelpers.poolConfiguration(host: "notworking"))
    }

    @Test
    func `Wrong port fails transiently and keeps the pool alive`() async throws {
        try await withTransientConfiguration(PostgresHelpers.poolConfiguration(port: 99999))
    }

    @Test
    func `Wrong username fails permanently`() async throws {
        try await withPermanentConfiguration(PostgresHelpers.poolConfiguration(username: "notworking")) { error in
            #expect(error.pgPoolDescription == "<PSQLError (code 28P01): FATAL: password authentication failed for user \"notworking\">")
        }
    }

    @Test
    func `Wrong password fails permanently`() async throws {
        try await withPermanentConfiguration(PostgresHelpers.poolConfiguration(password: "notworking")) { error in
            #expect(error.pgPoolDescription == "<PSQLError (code 28P01): FATAL: password authentication failed for user \"test_username\">")
        }
    }

    @Test
    func `Invalid TLS config fails permanently`() async throws {
        var tlsConfiguration: TLSConfiguration = .clientDefault
        tlsConfiguration.maximumTLSVersion = .tlsv1

        let tls: PostgresConnection.Configuration.TLS = try .require(.init(configuration: tlsConfiguration))
        try await withPermanentConfiguration(PostgresHelpers.poolConfiguration(tls: tls)) { error in
            let description = error.pgPoolDescription
            #expect(
                description.hasPrefix("<PSQLError: sslUnsupported")
                    || description.contains("handshakeFailed")
                    || description.contains("TLS"),
            )
            #expect(error.pgPoolDebugDescription.contains("code:"))
        }
    }

    // MARK: -

    /// Network and restart errors fail the request but leave the pool usable.
    private func withTransientConfiguration(
        _ configuration: PoolConfiguration,
    ) async throws {
        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

        var didFail = false

        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            Issue.record("Can't connect, so we should have an error here")
        }
        catch {
            if case PoolError.connectionFailed = error {
                didFail = true
            }
            else {
                Issue.record("Expected PoolError.connectionFailed, got \(error)")
            }
        }

        #expect(didFail)

        let info = await pool.poolInfo()
        #expect(info.isShutdown == false)
        #expect(info.shutdownError == nil)
        #expect(info.openConnections == 0)

        // A second request during the cooldown fails fast without a new attempt.
        await #expect(throws: PoolError.self) {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
        }

        await pool.shutdown()
    }

    /// Authentication, database-name and TLS configuration errors cannot
    /// recover without operator action, so the pool shuts down.
    private func withPermanentConfiguration(
        _ configuration: PoolConfiguration,
        verify: (PSQLError) -> Void,
    ) async throws {
        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

        var didFail = false

        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            Issue.record("Can't connect, so we should have an error here")
        }
        catch {
            if case PoolError.poolDestroyed = error {
                didFail = true
            }
            else {
                Issue.record("Expected PoolError.poolDestroyed, got \(error)")
            }
        }

        #expect(didFail)
        #expect(await pool.isShutdown)

        if let shutdownError = await pool.shutdownError {
            verify(shutdownError)
        }
        else {
            Issue.record("Expected shutdownError to be set")
        }
    }

}
