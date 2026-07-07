//
//  Created by Thomas Rasch on 07.07.26.
//

import Testing

@testable import PostgresConnectionPool

@Suite("PoolError")
struct PoolErrorTests {

    @Test("cancelled description")
    func cancelledDescription() {
        #expect(PoolError.cancelled.description == "<PoolError: cancelled>")
    }

    @Test("cancelled debugDescription")
    func cancelledDebugDescription() {
        #expect(PoolError.cancelled.debugDescription == "<PoolError: cancelled>")
    }

    @Test("connectionFailed description")
    func connectionFailedDescription() {
        #expect(PoolError.connectionFailed.description == "<PoolError: connectionFailed>")
    }

    @Test("connectionFailed debugDescription")
    func connectionFailedDebugDescription() {
        #expect(PoolError.connectionFailed.debugDescription == "<PoolError: connectionFailed>")
    }

    @Test("poolDestroyed without error description")
    func poolDestroyedNoErrorDescription() {
        let error = PoolError.poolDestroyed(nil)
        #expect(error.description == "<PoolError: poolDestroyed>")
    }

    @Test("poolDestroyed without error debugDescription")
    func poolDestroyedNoErrorDebugDescription() {
        let error = PoolError.poolDestroyed(nil)
        #expect(error.debugDescription == "<PoolError: poolDestroyed>")
    }

    @Test("unknown description")
    func unknownDescription() {
        #expect(PoolError.unknown.description == "<PoolError: unknown>")
    }

    @Test("unknown debugDescription")
    func unknownDebugDescription() {
        #expect(PoolError.unknown.debugDescription == "<PoolError: unknown>")
    }

    @Test("queryCancelled description and debugDescription")
    func queryCancelledDescriptions() {
        let error = PoolError.queryCancelled(query: "SELECT 1", runtime: 1.234)
        #expect(error.description == "<PoolError: queryCancelled>")
        #expect(error.debugDescription == "<PoolError: query 'SELECT 1' cancelled after 1.234s>")
    }

}
