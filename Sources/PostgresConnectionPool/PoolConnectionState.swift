//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation

public enum PoolConnectionState: Equatable {

    /// The connection is in use.
    case active(Date)
    /// The connection is open and available.
    case available
    /// The connection is closed and can't be used.
    case closed
    /// The connection is currently being established.
    case connecting

}
