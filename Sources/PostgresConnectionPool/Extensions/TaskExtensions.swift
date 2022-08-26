//
//  Created by Thomas Rasch on 25.08.22.
//

import Foundation

extension Task where Failure == Error {

    @discardableResult
    static func after(
        seconds: TimeInterval,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Success)
        -> Task
    {
        Task(priority: priority) {
            let delay = UInt64(seconds * 1_000_000_000)
            try await Task<Never, Never>.sleep(nanoseconds: delay)

            return try await operation()
        }
    }

}
