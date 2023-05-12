//
//  Created by Thomas Rasch on 01.04.22.
//

import Foundation
import PostgresNIO

final class PoolConnection: Identifiable, Equatable {

    // TODO: Serialize access
    private(set) static var connectionId = 0
    private(set) static var globalUsageCounter = 0

    private(set) var usageCounter = 0

    let id: Int
    var batchId: Int?

    var connection: PostgresConnection?
    var state: PoolConnectionState = .connecting {
        didSet {
            if case .active = state {
                usageCounter += 1
                PoolConnection.globalUsageCounter += 1
            }
        }
    }

    private var queryStartTimestamp: Date?
    var query: String? {
        didSet {
            queryStartTimestamp = (query == nil ? nil : Date())
        }
    }
    var queryRuntime: TimeInterval? {
        guard let queryStartTimestamp else { return nil }
        return Date().timeIntervalSince(queryStartTimestamp)
    }

    init() {
        self.id = PoolConnection.connectionId

        PoolConnection.connectionId += 1
    }

    static func == (lhs: PoolConnection, rhs: PoolConnection) -> Bool {
        lhs.id == rhs.id
    }

}
