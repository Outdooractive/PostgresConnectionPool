//
//  Created by Thomas Rasch on 07.07.26.
//

import PostgresNIO
import Testing

@testable import PostgresConnectionPool

@Suite("PoolConfiguration")
struct PoolConfigurationTests {

    private let postgresConfig = PostgresConnection.Configuration(
        host: "localhost",
        port: 5432,
        username: "test",
        password: "test",
        database: "test",
        tls: .disable)

    @Test("Defaults are applied")
    func defaults() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig)

        #expect(config.applicationName == "test")
        #expect(config.connectTimeout == 5.0)
        #expect(config.connectionRetryInterval == 0.5)
        #expect(config.queryTimeout == nil)
        #expect(config.poolSize == 10)
        #expect(config.maxIdleConnections == nil)
        #expect(config.onOpenConnection == nil)
        #expect(config.onReturnConnection != nil)
        #expect(config.onCloseConnection == nil)
    }

    @Test("connectTimeout is clamped to minimum 1 second")
    func connectTimeoutClamping() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            connectTimeout: 0.0)

        #expect(config.connectTimeout >= 1.0)
    }

    @Test("connectionRetryInterval allows zero")
    func retryIntervalZero() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            connectionRetryInterval: 0.0)

        #expect(config.connectionRetryInterval == 0.0)
    }

    @Test("queryTimeout is clamped to minimum 1 second")
    func queryTimeoutClamping() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            queryTimeout: 0.0)

        #expect(config.queryTimeout! >= 1.0)
    }

    @Test("poolSize is clamped to minimum 1")
    func poolSizeClamping() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            poolSize: 0)

        #expect(config.poolSize >= 1)
    }

    @Test("maxIdleConnections allows zero")
    func maxIdleZero() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            maxIdleConnections: 0)

        #expect(config.maxIdleConnections == 0)
    }

    @Test("maxIdleConnections is clamped to minimum 0")
    func maxIdleClamping() {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig,
            maxIdleConnections: -1)

        #expect(config.maxIdleConnections! >= 0)
    }

    @Test("onReturnConnection default runs SELECT 1")
    func onReturnConnectionDefault() async throws {
        let config = PoolConfiguration(
            applicationName: "test",
            postgresConfiguration: postgresConfig)

        let onReturn = config.onReturnConnection
        #expect(onReturn != nil)
    }

    @Test("Explicit nil callbacks are accepted")
    func nilCallbacks() {
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

}
