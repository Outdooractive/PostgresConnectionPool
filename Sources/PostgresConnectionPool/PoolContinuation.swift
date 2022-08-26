//
//  Created by Thomas Rasch on 01.04.22.
//

import Foundation
import PostgresNIO

typealias PostgresCheckedContinuation = CheckedContinuation<PoolConnection, Error>

final class PoolContinuation {

    let added: Date
    let continuation: PostgresCheckedContinuation

    init(continuation: PostgresCheckedContinuation) {
        self.added = Date()
        self.continuation = continuation
    }

}
