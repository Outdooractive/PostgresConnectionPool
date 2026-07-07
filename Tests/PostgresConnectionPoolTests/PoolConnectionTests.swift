//
//  Created by Thomas Rasch on 07.07.26.
//

import Foundation
import Testing

@testable import PostgresConnectionPool

@Suite("PoolConnection")
struct PoolConnectionTests {

    @Test("IDs are unique and incrementing")
    func uniqueIds() {
        let c1 = PoolConnection()
        let c2 = PoolConnection()
        #expect(c2.id > c1.id)
    }

    @Test("Initial state is connecting")
    func initialState() {
        let connection = PoolConnection()
        #expect(connection.state == .connecting)
    }

    @Test("State transitions to active increment usage counter")
    func activeIncrementsUsage() {
        let connection = PoolConnection()
        let before = connection.usageCounter.load(ordering: .relaxed)
        connection.state = .active(Date())
        let after = connection.usageCounter.load(ordering: .relaxed)
        #expect(after == before + 1)
    }

    @Test("State transitions to available does not increment usage")
    func availableDoesNotIncrementUsage() {
        let connection = PoolConnection()
        let before = connection.usageCounter.load(ordering: .relaxed)
        connection.state = .available
        #expect(connection.usageCounter.load(ordering: .relaxed) == before)
    }

    @Test("State transitions to closed does not increment usage")
    func closedDoesNotIncrementUsage() {
        let connection = PoolConnection()
        let before = connection.usageCounter.load(ordering: .relaxed)
        connection.state = .closed
        #expect(connection.usageCounter.load(ordering: .relaxed) == before)
    }

    @Test("Setting query sets queryStartTimestamp")
    func queryTracking() {
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

    @Test("Equality by id")
    func equality() {
        // PoolConnection ids are globally unique, so two instances are never equal.
        let c1 = PoolConnection()
        let c2 = PoolConnection()
        #expect(c1 != c2)
        #expect(c1 == c1)
    }

    @Test("Consecutive active transitions each increment usage")
    func multipleActiveTransitions() {
        let connection = PoolConnection()
        connection.state = .active(Date())
        connection.state = .available
        connection.state = .active(Date())
        connection.state = .available
        connection.state = .active(Date())

        #expect(connection.usageCounter.load(ordering: .relaxed) == 3)
    }

}
