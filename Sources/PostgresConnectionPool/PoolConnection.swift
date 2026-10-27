//
//  Created by Thomas Rasch on 01.04.22.
//

import Atomics
import Foundation
import PostgresNIO

final class PoolConnection: Identifiable, Equatable, @unchecked Sendable {

    /// For connection ids
    private static let connectionId: ManagedAtomic<Int> = .init(0)

    let usageCounter: ManagedAtomic<Int> = .init(0)

    let id: Int
    var batchId: Int?

    var connection: PostgresConnection?
    var state: PoolConnectionState = .connecting {
        didSet {
            if case .active = state {
                usageCounter.wrappingIncrement(by: 1, ordering: .relaxed)
            }
        }
    }

    private var queryStartTimestamp: Date?
    private let queryLock = NSLock()
    private var storedQuery: String?

    var query: String? {
        get {
            queryLock.lock()
            defer { queryLock.unlock() }
            return storedQuery
        }
        set {
            queryLock.lock()
            defer { queryLock.unlock() }

            storedQuery = newValue
            queryStartTimestamp = (newValue == nil ? nil : Date())
        }
    }

    var queryRuntime: TimeInterval? {
        queryLock.lock()
        defer { queryLock.unlock() }

        guard let queryStartTimestamp else { return nil }

        return Date().timeIntervalSince(queryStartTimestamp)
    }

    init() {
        self.id = PoolConnection.connectionId.loadThenWrappingIncrement(by: 1, ordering: .relaxed)
    }

    static func == (lhs: PoolConnection, rhs: PoolConnection) -> Bool {
        lhs.id == rhs.id
    }

}
