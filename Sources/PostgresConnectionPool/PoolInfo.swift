//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation

/// General information about the pool and its open connections.
public struct PoolInfo {

    /// Information about an open connection.
    public struct ConnectionInfo {
        public var id: Int
        public var name: String
        public var usageCounter: Int
        public var query: String?
        public var queryRuntime: TimeInterval?
        public var state: PoolConnectionState
    }

    public var name: String
    public var openConnections: Int
    public var activeConnections: Int
    public var availableConnections: Int

    public var connections: [ConnectionInfo]

}
