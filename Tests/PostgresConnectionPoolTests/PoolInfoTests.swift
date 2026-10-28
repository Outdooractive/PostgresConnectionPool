//
//  Created by Thomas Rasch on 07.07.26.
//

import Foundation
@testable import PostgresConnectionPool
import Testing

@Suite("PoolInfo")
struct PoolInfoTests {

    @Test
    func descriptionIncludesPoolNameAndConnectionCounts() {
        let connectionInfo = PoolInfo.ConnectionInfo(
            id: 1,
            name: "test - CONN:1",
            usageCounter: 5,
            batchId: nil,
            query: nil,
            queryRuntime: nil,
            state: .available)

        let info = PoolInfo(
            name: "user@localhost:5432/db",
            openConnections: 1,
            activeConnections: 0,
            availableConnections: 1,
            waitingRequests: 0,
            connections: [connectionInfo],
            isShutdown: false,
            shutdownError: nil)

        let desc = info.description
        #expect(desc.contains("user@localhost:5432/db"))
        #expect(desc.contains("Connections: 1/0/1"))
        #expect(desc.contains("Waiting requests: 0"))
        #expect(desc.contains("Is shut down? false"))
    }

    @Test
    func descriptionWithoutConnectionsOmitsConnectionDetails() {
        let info = PoolInfo(
            name: "pool",
            openConnections: 0,
            activeConnections: 0,
            availableConnections: 0,
            waitingRequests: 0,
            connections: [],
            isShutdown: false,
            shutdownError: nil)

        let desc = info.description
        #expect(desc.contains("Connection:") == false)
    }

    @Test
    func connectionInfoDescriptionFormat() {
        let info = PoolInfo.ConnectionInfo(
            id: 42,
            name: "app - CONN:42",
            usageCounter: 10,
            batchId: 7,
            query: "SELECT 1",
            queryRuntime: 0.123,
            state: .active(Date()))

        let desc = info.description
        #expect(desc.contains("Connection: 42"))
        #expect(desc.contains("app - CONN:42"))
        #expect(desc.contains("Usage: 10"))
        #expect(desc.contains("Query: SELECT 1"))
        #expect(desc.contains("Runtime: 0.123"))
        #expect(desc.contains("BatchId: 7"))
    }

    @Test
    func connectionInfoWithoutQueryOmitsQueryDetails() {
        let info = PoolInfo.ConnectionInfo(
            id: 1,
            name: "conn",
            usageCounter: 0,
            batchId: nil,
            query: nil,
            queryRuntime: nil,
            state: .available)

        let desc = info.description
        #expect(desc.contains("Query:") == false)
        #expect(desc.contains("Runtime:") == false)
        #expect(desc.contains("BatchId:") == false)
    }

}
