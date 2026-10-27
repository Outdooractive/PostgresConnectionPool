//
//  Created by Thomas Rasch on 07.07.26.
//

@testable import PostgresConnectionPool
import Testing

@Suite("PoolError")
struct PoolErrorTests {

    @Test
    func `cancelled localizedDescription`() {
        let error = PoolError.cancelled
        #expect(error.localizedDescription == "<PoolError: cancelled>")
    }

    @Test
    func `cancelled description`() {
        #expect(PoolError.cancelled.description == "<PoolError: cancelled>")
    }

    @Test
    func `cancelled debugDescription`() {
        #expect(PoolError.cancelled.debugDescription == "<PoolError: cancelled>")
    }

    @Test
    func `connectionFailed description`() {
        #expect(PoolError.connectionFailed.description == "<PoolError: connectionFailed>")
    }

    @Test
    func `connectionFailed debugDescription`() {
        #expect(PoolError.connectionFailed.debugDescription == "<PoolError: connectionFailed>")
    }

    @Test
    func `poolDestroyed without error description`() {
        let error = PoolError.poolDestroyed(nil)
        #expect(error.description == "<PoolError: poolDestroyed>")
    }

    @Test
    func `poolDestroyed without error debugDescription`() {
        let error = PoolError.poolDestroyed(nil)
        #expect(error.debugDescription == "<PoolError: poolDestroyed>")
    }

    @Test
    func `unknown description`() {
        #expect(PoolError.unknown.description == "<PoolError: unknown>")
    }

    @Test
    func `unknown debugDescription`() {
        #expect(PoolError.unknown.debugDescription == "<PoolError: unknown>")
    }

    @Test
    func `queryCancelled description and debugDescription`() {
        let error = PoolError.queryCancelled(query: "SELECT 1", runtime: 1.234)
        #expect(error.description == "<PoolError: queryCancelled>")
        #expect(error.debugDescription == "<PoolError: query 'SELECT 1' cancelled after 1.234s>")
    }

}
