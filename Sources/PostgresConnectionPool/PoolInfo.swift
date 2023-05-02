//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation

/// General information about the pool and its open connections.
public struct PoolInfo {

    /// Information about an open connection.
    public struct ConnectionInfo {
        public let id: Int
        public let name: String
        public let usageCounter: Int
        public let query: String?
        public let queryRuntime: TimeInterval?
        public let state: PoolConnectionState
    }

    public let name: String
    public let openConnections: Int
    public let activeConnections: Int
    public let availableConnections: Int
    public let usageCounter: Int

    public let connections: [ConnectionInfo]

}
