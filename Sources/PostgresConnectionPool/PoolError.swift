//
//  Created by Thomas Rasch on 08.08.22.
//

import Foundation
import PostgresNIO

/// Errors thrown by ``PostgresConnectionPool``.
public enum PoolError: Error, Sendable {

    /// The request was cancelled.
    case cancelled

    /// The connection to the database was unexpectedly closed.
    case connectionFailed

    /// The pool was already shut down.
    ///
    /// Contains the original `PSQLError` if the pool was shut down due to a
    /// permanent server error.
    case poolDestroyed(PSQLError?)

    /// A PostgreSQL error occurred during query execution.
    case postgresError(PSQLError)

    /// The query was cancelled by the server.
    case queryCancelled(query: String, runtime: Double)

    /// An unexpected error occurred.
    case unknown

}

// MARK: - CustomStringConvertible

extension PoolError: CustomStringConvertible {

    /// A short error description.
    public var description: String {
        switch self {
        case .cancelled:
            "<PoolError: cancelled>"

        case .connectionFailed:
            "<PoolError: connectionFailed>"

        case let .poolDestroyed(psqlError):
            if let psqlError {
                "<PoolError: poolDestroyed=\(psqlError.pgPoolDescription)>"
            }
            else {
                "<PoolError: poolDestroyed>"
            }

        case let .postgresError(psqlError):
            "<PoolError: postgresError=\(psqlError.pgPoolDescription)>"

        case .queryCancelled:
            "<PoolError: queryCancelled>"

        case .unknown:
            "<PoolError: unknown>"
        }
    }

}

// MARK: - LocalizedError

extension PoolError: LocalizedError {

    /// A human-readable error description.
    public var errorDescription: String? {
        description
    }

}

// MARK: - CustomDebugStringConvertible

extension PoolError: CustomDebugStringConvertible {

    /// A detailed error description suitable for debugging queries and other problems with the server.
    public var debugDescription: String {
        switch self {
        case .cancelled:
            "<PoolError: cancelled>"

        case .connectionFailed:
            "<PoolError: connectionFailed>"

        case let .poolDestroyed(psqlError):
            if let psqlError {
                "<PoolError: poolDestroyed=\(psqlError.pgPoolDebugDescription)>"
            }
            else {
                "<PoolError: poolDestroyed>"
            }

        case let .postgresError(psqlError):
            "<PoolError: postgresError=\(psqlError.pgPoolDebugDescription)>"

        case let .queryCancelled(query: query, runtime: runtime):
            "<PoolError: query '\(query)' cancelled after \(runtime.rounded(toPlaces: 3))s>"

        case .unknown:
            "<PoolError: unknown>"
        }
    }

}
