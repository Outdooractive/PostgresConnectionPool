//
//  Created by Thomas Rasch on 25.08.22.
//

import Foundation

extension Int {

    func atLeast(_ minValue: Int) -> Int {
        Swift.max(minValue, self)
    }

}
