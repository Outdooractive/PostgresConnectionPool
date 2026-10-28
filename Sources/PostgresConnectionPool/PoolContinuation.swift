//
//  Created by Thomas Rasch on 01.04.22.
//

import Atomics
import Foundation
import PostgresNIO

typealias PostgresCheckedContinuation = CheckedContinuation<PoolConnection, Error>

/// A cancellable cancellation marker shared between a waiting task and the
/// connection pool actor. The task cancellation handler can set the flag
/// without hopping onto the actor, and the actor can check it after enqueuing
/// the continuation to close the small race between cancellation and enqueue.
final class PoolContinuationCancellation: Sendable {

    private let cancelled = ManagedAtomic<Bool>(false)

    func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    var isCancelled: Bool {
        cancelled.load(ordering: .relaxed)
    }

}

final class PoolContinuation: @unchecked Sendable {

    let id: UUID
    let batchId: Int?
    let cancellation = PoolContinuationCancellation()
    let continuation: PostgresCheckedContinuation
    var healthCheckAttempt = 0

    init(
        id: UUID = UUID(),
        batchId: Int?,
        continuation: PostgresCheckedContinuation,
    ) {
        self.id = id
        self.batchId = batchId
        self.continuation = continuation
    }

}
