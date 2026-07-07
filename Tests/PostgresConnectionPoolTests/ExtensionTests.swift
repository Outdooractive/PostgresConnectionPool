//
//  Created by Thomas Rasch on 07.07.26.
//

import Collections
import Foundation
import Testing

@testable import PostgresConnectionPool

@Suite("Extensions")
struct ExtensionTests {

    // MARK: - isNotEmpty

    @Test("Array isNotEmpty")
    func arrayIsNotEmpty() {
        #expect([1].isNotEmpty)
        #expect(![Int]().isNotEmpty)
    }

    @Test("Deque isNotEmpty")
    func dequeIsNotEmpty() {
        var deque = Deque<Int>()
        #expect(!deque.isNotEmpty)
        deque.append(1)
        #expect(deque.isNotEmpty)
    }

    @Test("Dictionary isNotEmpty")
    func dictionaryIsNotEmpty() {
        #expect(["a": 1].isNotEmpty)
        #expect(![:].isNotEmpty)
    }

    @Test("Set isNotEmpty")
    func setIsNotEmpty() {
        #expect(Set([1]).isNotEmpty)
        #expect(!Set<Int>().isNotEmpty)
    }

    @Test("String isNotEmpty")
    func stringIsNotEmpty() {
        #expect("a".isNotEmpty)
        #expect(!"".isNotEmpty)
    }

    // MARK: - atLeast (Double)

    @Test("Double atLeast clamps below minimum")
    func doubleAtLeastClamp() {
        #expect(0.5.atLeast(1.0) == 1.0)
    }

    @Test("Double atLeast passes through above minimum")
    func doubleAtLeastPass() {
        #expect(2.0.atLeast(1.0) == 2.0)
    }

    @Test("Double atLeast equality")
    func doubleAtLeastEqual() {
        #expect(1.0.atLeast(1.0) == 1.0)
    }

    // MARK: - atLeast (Int)

    @Test("Int atLeast clamps below minimum")
    func intAtLeastClamp() {
        #expect(0.atLeast(1) == 1)
    }

    @Test("Int atLeast passes through above minimum")
    func intAtLeastPass() {
        #expect(5.atLeast(1) == 5)
    }

    @Test("Int atLeast equality")
    func intAtLeastEqual() {
        #expect(1.atLeast(1) == 1)
    }

    @Test("Int atLeast negative values")
    func intAtLeastNegative() {
        #expect((-5).atLeast(-10) == -5)
        #expect((-15).atLeast(-10) == -10)
    }

    // MARK: - FloatingPoint rounded(toPlaces:)

    @Test("Double rounded to places")
    func doubleRoundedToPlaces() {
        #expect(1.23456.rounded(toPlaces: 2) == 1.23)
        #expect(1.23556.rounded(toPlaces: 2) == 1.24)
    }

    @Test("Double rounded to zero places")
    func doubleRoundedToZero() {
        #expect(1.5.rounded(toPlaces: 0) == 2.0)
    }

    @Test("Double rounded to many places")
    func doubleRoundedToMany() {
        #expect(1.1.rounded(toPlaces: 10) == 1.1)
    }

    @Test("Double round mutating")
    func doubleRoundMutating() {
        var value = 1.23456
        value.round(toPlaces: 2)
        #expect(value == 1.23)
    }

    // MARK: - String.matches()

    @Test("String matches simple pattern")
    func stringMatchesSimple() {
        #expect("hello world".matches("hello"))
    }

    @Test("String matches regex pattern")
    func stringMatchesRegex() {
        #expect("abc123".matches("[a-z]+\\d+"))
    }

    @Test("String no match returns false")
    func stringNoMatch() {
        #expect(!"abc".matches("\\d+"))
    }

    @Test("String matches case insensitive")
    func stringMatchesCaseInsensitive() {
        #expect("Hello".matches("hello", caseInsensitive: true))
        #expect(!"Hello".matches("hello"))
    }

    // MARK: - String.replacingPattern()

    @Test("String replacingPattern basic")
    func replacingPatternBasic() {
        let result = "hello 123 world".replacingPattern("\\d+", with: "NUM")
        #expect(result == "hello NUM world")
    }

    @Test("String replacingPattern no match")
    func replacingPatternNoMatch() {
        let result = "hello".replacingPattern("\\d+", with: "NUM")
        #expect(result == "hello")
    }

    @Test("String replacingPattern case insensitive")
    func replacingPatternCaseInsensitive() {
        let result = "Hello World".replacingPattern("hello", with: "Hi", caseInsensitive: true)
        #expect(result == "Hi World")
    }

    @Test("String replacingPattern invalid regex returns self")
    func replacingPatternInvalidRegex() {
        let result = "hello".replacingPattern("[invalid", with: "")
        #expect(result == "hello")
    }

}
