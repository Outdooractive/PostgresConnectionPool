//
//  Created by Thomas Rasch on 11.05.23.
//

@testable import PostgresConnectionPool
import PostgresNIO
import XCTest

final class ConnectionTests: XCTestCase {

    private var logger: Logger = {
        var logger = Logger(label: "ConnectionTests")
        logger.logLevel = .info
        return logger
    }()

    // MARK: -

    // Test that the pool can actually connect to the server.
    func testCanConnect() async throws {
        let pool = PostgresConnectionPool(configuration: PostgresHelpers.poolConfiguration(), logger: logger)

        do {
            try await pool.connection { connection in
                try await connection.query("SELECT 1", logger: logger)
            }
            await pool.shutdown()
        }
        catch {
            XCTFail("Is the cocker container running? (\(String(describing: (error as? PoolError)?.debugDescription))")
        }

        let didShutdown = await pool.isShutdown
        XCTAssertTrue(didShutdown)
    }

    func testPoolInfo() async throws {
        let pool = PostgresConnectionPool(configuration: PostgresHelpers.poolConfiguration(), logger: logger)

        let poolInfoBefore = await pool.poolInfo()
        print(poolInfoBefore)
        XCTAssertEqual(poolInfoBefore.activeConnections, 0)
        XCTAssertEqual(poolInfoBefore.availableConnections, 0)
        XCTAssertEqual(poolInfoBefore.openConnections, 0)
        XCTAssertEqual(poolInfoBefore.connections.count, poolInfoBefore.openConnections)
        XCTAssertFalse(poolInfoBefore.isShutdown)
        XCTAssertNil(poolInfoBefore.shutdownError)

        let start = 1
        let end = 1000

        await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for _ in 1 ... 1000 {
                taskGroup.addTask {
                    try await pool.connection { connection in
                        _ = try await connection.query("SELECT generate_series(\(start), \(end));", logger: self.logger)
                    }
                }
            }
        }

        let poolInfo = await pool.poolInfo()
        print(poolInfo)
        XCTAssertEqual(poolInfo.activeConnections, 0)
        XCTAssertGreaterThan(poolInfo.availableConnections, 0)
        XCTAssertGreaterThan(poolInfo.openConnections, 0)
        XCTAssertEqual(poolInfo.connections.count, poolInfo.openConnections)
        XCTAssertFalse(poolInfo.isShutdown)
        XCTAssertNil(poolInfo.shutdownError)

        await pool.shutdown()

        let poolInfoAfterShutdown = await pool.poolInfo()
        print(poolInfoAfterShutdown)
        XCTAssertEqual(poolInfoAfterShutdown.activeConnections, 0)
        XCTAssertEqual(poolInfoAfterShutdown.availableConnections, 0)
        XCTAssertEqual(poolInfoAfterShutdown.openConnections, 0)
        XCTAssertEqual(poolInfoAfterShutdown.connections.count, 0)
        XCTAssertTrue(poolInfoAfterShutdown.isShutdown)
        XCTAssertNil(poolInfoAfterShutdown.shutdownError)
    }

    func testPoolSize100() async throws {
        let pool = PostgresConnectionPool(configuration: PostgresHelpers.poolConfiguration(poolSize: 100), logger: logger)

        let start = 1
        let end = 100

        await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for _ in 1 ... 10000 {
                taskGroup.addTask {
                    try await pool.connection { connection in
                        _ = try await connection.query("SELECT generate_series(\(start), \(end));", logger: self.logger)
                    }
                }
            }
        }

        let poolInfo = await pool.poolInfo()
        XCTAssertEqual(poolInfo.activeConnections, 0)
        XCTAssertGreaterThan(poolInfo.availableConnections, 0)
        XCTAssertGreaterThan(poolInfo.openConnections, 0)
        XCTAssertEqual(poolInfo.connections.count, poolInfo.openConnections)
        XCTAssertFalse(poolInfo.isShutdown)
        XCTAssertNil(poolInfo.shutdownError)

        await pool.closeIdleConnections()

        let poolInfoIdleClosed = await pool.poolInfo()
        XCTAssertEqual(poolInfoIdleClosed.activeConnections, 0)
        XCTAssertEqual(poolInfoIdleClosed.availableConnections, 0)
        XCTAssertEqual(poolInfoIdleClosed.openConnections, 0)
        XCTAssertEqual(poolInfoIdleClosed.connections.count, poolInfoIdleClosed.openConnections)
        XCTAssertFalse(poolInfoIdleClosed.isShutdown)
        XCTAssertNil(poolInfoIdleClosed.shutdownError)

        await pool.shutdown()
    }

}
