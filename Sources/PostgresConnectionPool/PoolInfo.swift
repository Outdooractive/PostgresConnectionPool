//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation
import PostgresNIO

/// General information about the pool and its open connections.
public struct PoolInfo {

    /// Information about an open connection.
    public struct ConnectionInfo {
        /// The unique connection id.
        public let id: Int
        /// The connection name on the server.
        public let name: String
        /// Total number of queries that were sent over this connection.
        public let usageCounter: Int
        /// The connection's batch Id.
        public var batchId: Int?
        /// The current query, if available.
        public let query: String?
        /// The current time for the query, if available.
        public let queryRuntime: TimeInterval?
        /// The state of the connection, see ``PoolConnectionState``.
        public let state: PoolConnectionState
    }

    /// The name of the pool which is usually something like the Postgres connection string.
    public let name: String
    /// The total number of open connections to the server.
    public let openConnections: Int
    /// The number of connections that are currently in use.
    public let activeConnections: Int
    /// The number of connections that are currently available.
    public let availableConnections: Int
    /// The total number of queries that were sent to the server.
    public let usageCounter: Int

    /// Information about individual open connections to the server.
    public let connections: [ConnectionInfo]


    /// Whether the pool is accepting connections or was shutdown.
    public let isShutdown: Bool
    /// The Postgres error If the pool was shutdown forcibly.
    public let shutdownError: PSQLError?

}

// MARK: - CustomStringConvertible

extension PoolInfo: CustomStringConvertible {

    public var description: String {
        var lines: [String] = [
            "Pool: \(name)",
            "Connections: \(openConnections)/\(activeConnections)/\(availableConnections) (open/active/available)",
            "Usage: \(usageCounter)",
            "Shutdown? \(isShutdown) \(shutdownError != nil ? "(\(shutdownError!.description))" : "")",
        ]

        if connections.isNotEmpty {
            lines.append("Connections:")

            for connection in connections.sorted(by: { $0.id < $1.id }) {
                lines.append(contentsOf: connection.description.components(separatedBy: "\n").map({ "  " + $0 }))
            }
        }

        return lines.joined(separator: "\n")
    }

}

extension PoolInfo.ConnectionInfo: CustomStringConvertible {

    public var description: String {
        var lines: [String] = [
            "Connection: \(id) (\(name))",
            "  State: \(state)",
            "  Usage: \(usageCounter)",
        ]

        if let query {
            lines.append("  Query: \(query)")
            if let queryRuntime {
                lines.append("  Runtime: \(queryRuntime.rounded(toPlaces: 3))s")
            }
        }

        if let batchId {
            lines.append("  BatchId: \(batchId)")
        }

        return lines.joined(separator: "\n")
    }

}
