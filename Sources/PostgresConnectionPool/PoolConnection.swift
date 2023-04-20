//
//  Created by Thomas Rasch on 01.04.22.
//

import Foundation
import PostgresNIO

final class PoolConnection: Identifiable, Equatable {

    enum State: Equatable {
        case active(Date)
        case available
        case closed
        case connecting
    }

    private static var connectionId: Int = 0

    private(set) var usageCounter = 0

    let id: Int
    var connection: PostgresConnection?
    var state: State = .connecting {
        didSet {
            if case .active = state { usageCounter += 1 }
        }
    }

    init() {
        self.id = PoolConnection.connectionId

        PoolConnection.connectionId += 1
    }

    static func == (lhs: PoolConnection, rhs: PoolConnection) -> Bool {
        lhs.id == rhs.id
    }

}
