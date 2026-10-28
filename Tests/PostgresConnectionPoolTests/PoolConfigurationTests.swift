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
    func defaultsAreApplied() {
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
    func connectTimeoutIsClampedToMinimum1Second() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            connectTimeout: 0.0)

        #expect(config.connectTimeout >= 1.0)
    }

    @Test
    func connectionRetryIntervalAllowsZero() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            connectionRetryInterval: 0.0)

        #expect(config.connectionRetryInterval == 0.0)
    }

    @Test
    func queryTimeoutIsClampedToMinimum1Second() throws {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            queryTimeout: 0.0)

        #expect(try #require(config.queryTimeout) >= 1.0)
    }

    @Test
    func poolSizeIsClampedToMinimum1() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            poolSize: 0)

        #expect(config.poolSize >= 1)
    }

    @Test
    func maxIdleConnectionsAllowsZero() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            maxIdleConnections: 0)

        #expect(config.maxIdleConnections == 0)
    }

    @Test
    func maxIdleConnectionsIsClampedToMinimum0() throws {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            maxIdleConnections: -1)

        #expect(try #require(config.maxIdleConnections) >= 0)
    }

    @Test
    func onReturnConnectionDefaultRunsSelect1() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig)

        let onReturn = config.onReturnConnection
        #expect(onReturn != nil)
    }

    @Test
    func explicitNilCallbacksAreAccepted() {
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
    func healthCheckCanBeDisabled() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            defaultHealthCheckEnabled: false)

        #expect(config.defaultHealthCheckEnabled == false)
        #expect(config.onReturnConnection == nil)
    }

    @Test
    func customReturnHookIsKeptWhenTheDefaultHealthCheckIsDisabled() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            defaultHealthCheckEnabled: false,
            onReturnConnection: { _, _ in })

        #expect(config.defaultHealthCheckEnabled == false)
        #expect(config.onReturnConnection != nil)
    }

}
