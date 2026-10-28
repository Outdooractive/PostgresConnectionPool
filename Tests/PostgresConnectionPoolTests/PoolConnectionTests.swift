//
//  Created by Thomas Rasch on 07.07.26.
//

import Foundation
@testable import PostgresConnectionPool
import Testing

@Suite("PoolConnection")
struct PoolConnectionTests {

    @Test
    func iDsAreUniqueAndIncrementing() {
        let c1 = PoolConnection()
        let c2 = PoolConnection()
        #expect(c2.id > c1.id)
    }

    @Test
    func initialStateIsConnecting() {
        let connection = PoolConnection()
        #expect(connection.state == .connecting)
    }

    @Test
    func stateTransitionsToActiveIncrementUsageCounter() {
        let connection = PoolConnection()
        let before = connection.usageCounter.load(ordering: .relaxed)
        connection.state = .active(Date())
        let after = connection.usageCounter.load(ordering: .relaxed)
        #expect(after == before + 1)
    }

    @Test
    func stateTransitionsToAvailableDoesNotIncrementUsage() {
        let connection = PoolConnection()
        let before = connection.usageCounter.load(ordering: .relaxed)
        connection.state = .available
        #expect(connection.usageCounter.load(ordering: .relaxed) == before)
    }

    @Test
    func stateTransitionsToClosedDoesNotIncrementUsage() {
        let connection = PoolConnection()
        let before = connection.usageCounter.load(ordering: .relaxed)
        connection.state = .closed
        #expect(connection.usageCounter.load(ordering: .relaxed) == before)
    }

    @Test
    func settingQuerySetsQueryStartTimestamp() {
        let connection = PoolConnection()
        #expect(connection.query == nil)
        #expect(connection.queryRuntime == nil)

        connection.query = "SELECT 1"
        #expect(connection.query == "SELECT 1")
        #expect(connection.queryRuntime != nil)

        connection.query = nil
        #expect(connection.query == nil)
        #expect(connection.queryRuntime == nil)
    }

    @Test
    func equalityById() {
        // PoolConnection ids are globally unique, so two instances are never equal.
        let c1 = PoolConnection()
        let c2 = PoolConnection()
        #expect(c1 != c2)
        #expect(c1 == c1)
    }

    @Test
    func consecutiveActiveTransitionsEachIncrementUsage() {
        let connection = PoolConnection()
        connection.state = .active(Date())
        connection.state = .available
        connection.state = .active(Date())
        connection.state = .available
        connection.state = .active(Date())

        #expect(connection.usageCounter.load(ordering: .relaxed) == 3)
    }

}
