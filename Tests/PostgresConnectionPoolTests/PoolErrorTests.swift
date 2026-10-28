//
//  Created by Thomas Rasch on 07.07.26.
//

@testable import PostgresConnectionPool
import Testing

@Suite("PoolError")
struct PoolErrorTests {

    @Test
    func cancelledLocalizedDescription() {
        let error = PoolError.cancelled
        #expect(error.localizedDescription == "<PoolError: cancelled>")
    }

    @Test
    func cancelledDescription() {
        #expect(PoolError.cancelled.description == "<PoolError: cancelled>")
    }

    @Test
    func cancelledDebugDescription() {
        #expect(PoolError.cancelled.debugDescription == "<PoolError: cancelled>")
    }

    @Test
    func connectionFailedDescription() {
        #expect(PoolError.connectionFailed.description == "<PoolError: connectionFailed>")
    }

    @Test
    func connectionFailedDebugDescription() {
        #expect(PoolError.connectionFailed.debugDescription == "<PoolError: connectionFailed>")
    }

    @Test
    func poolDestroyedWithoutErrorDescription() {
        let error = PoolError.poolDestroyed(nil)
        #expect(error.description == "<PoolError: poolDestroyed>")
    }

    @Test
    func poolDestroyedWithoutErrorDebugDescription() {
        let error = PoolError.poolDestroyed(nil)
        #expect(error.debugDescription == "<PoolError: poolDestroyed>")
    }

    @Test
    func unknownDescription() {
        #expect(PoolError.unknown.description == "<PoolError: unknown>")
    }

    @Test
    func unknownDebugDescription() {
        #expect(PoolError.unknown.debugDescription == "<PoolError: unknown>")
    }

    @Test
    func queryCancelledDescriptionAndDebugDescription() {
        let error = PoolError.queryCancelled(query: "SELECT 1", runtime: 1.234)
        #expect(error.description == "<PoolError: queryCancelled>")
        #expect(error.debugDescription == "<PoolError: query 'SELECT 1' cancelled after 1.234s>")
    }

}
