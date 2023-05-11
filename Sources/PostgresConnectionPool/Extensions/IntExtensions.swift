//
//  Created by Thomas Rasch on 25.08.22.
//

import Foundation

extension Int {

    /// Returns the maximum of `self` and the other value.
    func atLeast(_ minValue: Int) -> Int {
        Swift.max(minValue, self)
    }

}
