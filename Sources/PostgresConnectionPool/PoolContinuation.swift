//
//  Created by Thomas Rasch on 01.04.22.
//

import Foundation
import PostgresNIO

typealias PostgresCheckedContinuation = CheckedContinuation<PoolConnection, Error>

final class PoolContinuation: Sendable {

    let added: Date
    let batchId: Int?
    let continuation: PostgresCheckedContinuation

    init(batchId: Int?, continuation: PostgresCheckedContinuation) {
        self.added = Date()
        self.batchId = batchId
        self.continuation = continuation
    }

}
