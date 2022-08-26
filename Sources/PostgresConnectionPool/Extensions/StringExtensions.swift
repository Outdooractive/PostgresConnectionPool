//
//  Created by Thomas Rasch on 25.08.22.
//

import Foundation

// MARK: Regexp

extension String {

    func matches(
        _ regexp: String,
        caseInsensitive: Bool = false)
        -> Bool
    {
        var options: String.CompareOptions = .regularExpression
        if caseInsensitive { options.insert(.caseInsensitive) }

        return self.range(of: regexp, options: options) != nil
    }

    func replacingPattern(
        _ regexp: String,
        with replacement: String,
        caseInsensitive: Bool = false,
        treatAsOneLine: Bool = false)
        -> String
    {
        var options = NSRegularExpression.Options()

        if caseInsensitive { options.insert(.caseInsensitive) }
        if treatAsOneLine { options.insert(.dotMatchesLineSeparators) }

        guard let pattern = try? NSRegularExpression(pattern: regexp, options: options) else {
            return self
        }

        return pattern.stringByReplacingMatches(
            in: self,
            options: NSRegularExpression.MatchingOptions(),
            range: NSRange(location: 0, length: self.count),
            withTemplate: replacement)
    }

}
