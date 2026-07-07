//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation

/// The state of a pooled database connection.
public enum PoolConnectionState: Equatable, Sendable {

    /// The connection is currently in use. The associated value is the activation timestamp.
    case active(Date)

    /// The connection is open and available for reuse.
    case available

    /// The connection is closed and can no longer be used.
    case closed

    /// The connection is currently being established.
    case connecting

}
