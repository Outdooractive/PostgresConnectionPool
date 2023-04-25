//
//  Created by Thomas Rasch on 24.04.23.
//

import Foundation

public enum PoolConnectionState: Equatable {
    case active(Date)
    case available
    case closed
    case connecting
}
