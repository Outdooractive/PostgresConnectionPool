//
//  Created by Thomas Rasch on 08.08.22.
//

import Foundation
import PostgresNIO

/// Possible errors from the connection pool.
public enum PoolError: Error, Sendable {

    /// The request was cancelled.
    case cancelled
    /// The connection to the database was unexpectedly closed.
    case connectionFailed
    /// The pool was already shut down. Includes the original `PSQLError`
    /// if the pool was shutdown due to a permanent server error.
    case poolDestroyed(PSQLError?)
    /// Some PostgreSQL error.
    case postgresError(PSQLError)
    /// The query was cancelled by the server.
    case queryCancelled(query: String, runtime: Double)
    /// Something unexpected happened.
    case unknown

}

// MARK: - CustomStringConvertible

extension PoolError: CustomStringConvertible {

    /// A short error description.
    public var description: String {
        switch self {
        case .cancelled:
            return "<PoolError: cancelled>"

        case .connectionFailed:
            return "<PoolError: connectionFailed>"

        case .poolDestroyed(let psqlError):
            if let psqlError {
                return "<PoolError: poolDestroyed=\(psqlError.description)>"
            }
            else {
                return "<PoolError: poolDestroyed>"
            }

        case .postgresError(let psqlError):
            return "<PoolError: postgresError=\(psqlError.description)>"

        case .queryCancelled:
            return "<PoolError: queryCancelled>"

        case .unknown:
            return "<PoolError: unknown>"
        }
    }

}

// MARK: - CustomDebugStringConvertible

extension PoolError: CustomDebugStringConvertible {

    /// A detailed error description suitable for debugging queries and other problems with the server.
    public var debugDescription: String {
        switch self {
        case .cancelled:
            return "<PoolError: cancelled>"

        case .connectionFailed:
            return "<PoolError: connectionFailed>"

        case .poolDestroyed(let psqlError):
            if let psqlError {
                return "<PoolError: poolDestroyed=\(psqlError.debugDescription)>"
            }
            else {
                return "<PoolError: poolDestroyed>"
            }

        case .postgresError(let psqlError):
            return "<PoolError: postgresError=\(psqlError.debugDescription)>"

        case .queryCancelled(query: let query, runtime: let runtime):
            return "<PoolError: query '\(query)' cancelled after \(runtime.rounded(toPlaces: 3))s>"

        case .unknown:
            return "<PoolError: unknown>"
        }
    }

}
