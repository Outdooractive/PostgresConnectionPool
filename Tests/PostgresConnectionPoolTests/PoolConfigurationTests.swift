//
//  Created by Thomas Rasch on 07.07.26.
//

@testable import PostgresConnectionPool
import PostgresNIO
import Testing

@Suite("PoolConfiguration")
struct PoolConfigurationTests {

    private let postgresConfig = PostgresConnection.Configuration(
        host: "localhost",
        port: 5432,
        username: "test",
        password: "test",
        database: "test",
        tls: .disable)

    @Test
    func `Defaults are applied`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig)

        #expect(config.applicationName == "test")
        #expect(config.connectTimeout == 5.0)
        #expect(config.connectionRetryInterval == 0.5)
        #expect(config.queryTimeout == nil)
        #expect(config.poolSize == 10)
        #expect(config.maxIdleConnections == nil)
        #expect(config.defaultHealthCheckEnabled)
        #expect(config.onOpenConnection == nil)
        #expect(config.onReturnConnection != nil)
        #expect(config.onCloseConnection == nil)
    }

    @Test
    func `connectTimeout is clamped to minimum 1 second`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            connectTimeout: 0.0)

        #expect(config.connectTimeout >= 1.0)
    }

    @Test
    func `connectionRetryInterval allows zero`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            connectionRetryInterval: 0.0)

        #expect(config.connectionRetryInterval == 0.0)
    }

    @Test
    func `queryTimeout is clamped to minimum 1 second`() throws {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            queryTimeout: 0.0)

        #expect(try #require(config.queryTimeout) >= 1.0)
    }

    @Test
    func `poolSize is clamped to minimum 1`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            poolSize: 0)

        #expect(config.poolSize >= 1)
    }

    @Test
    func `maxIdleConnections allows zero`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            maxIdleConnections: 0)

        #expect(config.maxIdleConnections == 0)
    }

    @Test
    func `maxIdleConnections is clamped to minimum 0`() throws {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            maxIdleConnections: -1)

        #expect(try #require(config.maxIdleConnections) >= 0)
    }

    @Test
    func `onReturnConnection default runs SELECT 1`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig)

        let onReturn = config.onReturnConnection
        #expect(onReturn != nil)
    }

    @Test
    func `Explicit nil callbacks are accepted`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            onOpenConnection: nil,
            onReturnConnection: nil,
            onCloseConnection: nil)

        #expect(config.onOpenConnection == nil)
        #expect(config.onReturnConnection != nil) // default
        #expect(config.onCloseConnection == nil)
    }

    @Test
    func `Health check can be disabled`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            defaultHealthCheckEnabled: false)

        #expect(config.defaultHealthCheckEnabled == false)
        #expect(config.onReturnConnection == nil)
    }

    @Test
    func `Custom return hook is kept when the default health check is disabled`() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            defaultHealthCheckEnabled: false,
            onReturnConnection: { _, _ in })

        #expect(config.defaultHealthCheckEnabled == false)
        #expect(config.onReturnConnection != nil)
    }

}
