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
    /// Some PostgreSQL error
    case postgresError(PSQLError)
    /// The query was cancelled by the server.
    case queryCancelled
    /// Something unexpected happened.
    case unknown

}
