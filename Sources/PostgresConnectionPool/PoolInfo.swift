//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation
import PostgresNIO

/// Diagnostic information about a ``PostgresConnectionPool`` and its connections.
public struct PoolInfo: Sendable {

    /// Information about a single open connection in the pool.
    public struct ConnectionInfo: Sendable {
        /// The unique connection identifier.
        public let id: Int

        /// The connection display name (as sent to PostgreSQL via `application_name`).
        public let name: String

        /// Total number of queries executed on this connection.
        public let usageCounter: Int

        /// The optional batch ID associated with this connection.
        public var batchId: Int?

        /// The SQL text of the currently running query, if any.
        public let query: String?

        /// The elapsed time of the currently running query, if any.
        public let queryRuntime: TimeInterval?

        /// The current state of the connection.
        public let state: PoolConnectionState
    }

    /// A human-readable name for the pool (typically the Postgres connection string).
    public let name: String

    /// The total number of open connections.
    public let openConnections: Int

    /// The number of connections currently in use.
    public let activeConnections: Int

    /// The number of idle connections available for reuse.
    public let availableConnections: Int

    /// Detailed information about each open connection.
    public let connections: [ConnectionInfo]

    /// Whether the pool has been shut down.
    public let isShutdown: Bool

    /// The error that caused the pool to shut down, if any.
    public let shutdownError: PSQLError?

}

// MARK: - CustomStringConvertible

extension PoolInfo: CustomStringConvertible {

    public var description: String {
        var lines: [String] = [
            "Pool: \(name)",
            "  Connections: \(openConnections)/\(activeConnections)/\(availableConnections) (open/active/available)",
            "  Is shut down? \(isShutdown) \(shutdownError.map({ "(\($0.description))" }) ?? "")",
        ]

        if connections.isNotEmpty {
            lines.append("  Connections:")

            for connection in connections.sorted(by: { $0.id < $1.id }) {
                lines.append(contentsOf: connection.description.components(separatedBy: "\n").map({ "    " + $0 }))
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
