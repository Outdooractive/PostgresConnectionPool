//
//  Created by Thomas Rasch on 11.05.23.
//

@testable import PostgresConnectionPool
import PostgresNIO
import Testing

@Suite("Connection Tests", .serialized, .enabled(if: PostgresHelpers.isAvailable))
struct ConnectionTests {

    private let logger: Logger = {
        var logger = Logger(label: "ConnectionTests")
        logger.logLevel = .info
        return logger
    }()

    @Test
    func `Can connect and execute a query`() async throws {
        let pool = PostgresConnectionPool(configuration: PostgresHelpers.poolConfiguration(), logger: logger)

        try await pool.connection { connection in
            try await connection.query("SELECT 1", logger: logger)
        }
        await pool.shutdown()

        let didShutdown = await pool.isShutdown
        #expect(didShutdown)
    }

    @Test
    func `Pool info reflects state correctly`() async throws {
        let pool = PostgresConnectionPool(configuration: PostgresHelpers.poolConfiguration(), logger: logger)

        let poolInfoBefore = await pool.poolInfo()
        print(poolInfoBefore)
        #expect(poolInfoBefore.activeConnections == 0)
        #expect(poolInfoBefore.availableConnections == 0)
        #expect(poolInfoBefore.openConnections == 0)
        #expect(poolInfoBefore.connections.count == poolInfoBefore.openConnections)
        #expect(poolInfoBefore.isShutdown == false)
        #expect(poolInfoBefore.shutdownError == nil)

        let start = 1
        let end = 100

        try await withThrowingDiscardingTaskGroup { taskGroup in
            for _ in 1 ... 200 {
                taskGroup.addTask {
                    try await pool.connection { connection in
                        _ = try await connection.query("SELECT generate_series(\(start), \(end));", logger: logger)
                    }
                }
            }
        }

        let poolInfo = await pool.poolInfo()
        print(poolInfo)
        #expect(poolInfo.activeConnections == 0)
        #expect(poolInfo.availableConnections > 0)
        #expect(poolInfo.openConnections > 0)
        #expect(poolInfo.connections.count == poolInfo.openConnections)
        #expect(poolInfo.isShutdown == false)
        #expect(poolInfo.shutdownError == nil)

        await pool.shutdown()

        let poolInfoAfterShutdown = await pool.poolInfo()
        print(poolInfoAfterShutdown)
        #expect(poolInfoAfterShutdown.activeConnections == 0)
        #expect(poolInfoAfterShutdown.availableConnections == 0)
        #expect(poolInfoAfterShutdown.openConnections == 0)
        #expect(poolInfoAfterShutdown.connections.isEmpty)
        #expect(poolInfoAfterShutdown.isShutdown)
        #expect(poolInfoAfterShutdown.shutdownError == nil)
    }

    @Test
    func `Pool with 20 connections handles 2000 queries`() async throws {
        let pool = PostgresConnectionPool(configuration: PostgresHelpers.poolConfiguration(poolSize: 20), logger: logger)

        let start = 1
        let end = 100

        try await withThrowingDiscardingTaskGroup { taskGroup in
            for _ in 1 ... 2000 {
                taskGroup.addTask {
                    try await pool.connection { connection in
                        _ = try await connection.query("SELECT generate_series(\(start), \(end));", logger: logger)
                    }
                }
            }
        }

        let poolInfo = await pool.poolInfo()
        #expect(poolInfo.activeConnections == 0)
        #expect(poolInfo.availableConnections > 0)
        #expect(poolInfo.openConnections > 0)
        #expect(poolInfo.connections.count == poolInfo.openConnections)
        #expect(poolInfo.isShutdown == false)
        #expect(poolInfo.shutdownError == nil)

        await pool.closeIdleConnections()

        let poolInfoIdleClosed = await pool.poolInfo()
        #expect(poolInfoIdleClosed.activeConnections == 0)
        #expect(poolInfoIdleClosed.availableConnections == 0)
        #expect(poolInfoIdleClosed.openConnections == 0)
        #expect(poolInfoIdleClosed.connections.count == poolInfoIdleClosed.openConnections)
        #expect(poolInfoIdleClosed.isShutdown == false)
        #expect(poolInfoIdleClosed.shutdownError == nil)

        await pool.shutdown()
    }

}
