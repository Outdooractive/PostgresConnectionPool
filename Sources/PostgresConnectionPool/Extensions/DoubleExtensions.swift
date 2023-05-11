//
//  Created by Thomas Rasch on 14.04.22.
//

import Foundation

extension Double {

    /// Returns the maximum of `self` and the other value.
    func atLeast(_ minValue: Double) -> Double {
        Swift.max(minValue, self)
    }

}
