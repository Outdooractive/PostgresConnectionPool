//
//  Created by Thomas Rasch on 14.04.22.
//

import Foundation

extension Double {

    func atLeast(_ minValue: Double) -> Double {
        Swift.max(minValue, self)
    }

}
