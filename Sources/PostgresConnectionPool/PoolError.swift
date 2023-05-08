//
//  Created by Thomas Rasch on 08.08.22.
//

import Foundation
import PostgresNIO

/// Possible errors from the connection pool.
public enum PoolError: Error {

    /// The request was cancelled.
    case cancelled
    /// The connection to the database was unexpectedly closed.
    case connectionFailed
    /// The pool was already shut down.
    case poolDestroyed
    /// Some PostgreSQL error.
    case postgresError(PSQLError)
    /// The query was cancelled by the server.
    case queryCancelled(query: String, runtime: Double)
    /// Something unexpected happened.
    case unknown

}

extension PoolError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .cancelled: return "<PoolError: cancelled>"
        case .connectionFailed: return "<PoolError: connectionFailed>"
        case .poolDestroyed: return "<PoolError: poolDestroyed>"
        case .postgresError(let psqlError): return "<PoolError: postgresError='\(psqlError.description)'>"
        case .queryCancelled(query: let query, runtime: let runtime): return "<PoolError: query '\(query)' cancelled after \(runtime.rounded(toPlaces: 3))s>"
        case .unknown: return "<PoolError: unknown>"
        }
    }

}
