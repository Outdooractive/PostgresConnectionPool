//
//  Created by Thomas Rasch on 07.07.26.
//

import Collections
import Foundation
@testable import PostgresConnectionPool
import Testing

@Suite("Extensions")
struct ExtensionTests {

    // MARK: - isNotEmpty

    @Test
    func `Array isNotEmpty`() {
        #expect([1].isNotEmpty)
        #expect([Int]().isNotEmpty == false)
    }

    @Test
    func `Deque isNotEmpty`() {
        var deque = Deque<Int>()
        #expect(deque.isNotEmpty == false)
        deque.append(1)
        #expect(deque.isNotEmpty)
    }

    @Test
    func `Dictionary isNotEmpty`() {
        #expect(["a": 1].isNotEmpty)
        #expect([:].isNotEmpty == false)
    }

    @Test
    func `Set isNotEmpty`() {
        #expect(Set([1]).isNotEmpty)
        #expect(Set<Int>().isNotEmpty == false)
    }

    @Test
    func `String isNotEmpty`() {
        #expect("a".isNotEmpty)
        #expect("".isNotEmpty == false)
    }

    // MARK: - atLeast (Double)

    @Test
    func `Double atLeast clamps below minimum`() {
        #expect(0.5.atLeast(1.0) == 1.0)
    }

    @Test
    func `Double atLeast passes through above minimum`() {
        #expect(2.0.atLeast(1.0) == 2.0)
    }

    @Test
    func `Double atLeast equality`() {
        #expect(1.0.atLeast(1.0) == 1.0)
    }

    // MARK: - atLeast (Int)

    @Test
    func `Int atLeast clamps below minimum`() {
        #expect(0.atLeast(1) == 1)
    }

    @Test
    func `Int atLeast passes through above minimum`() {
        #expect(5.atLeast(1) == 5)
    }

    @Test
    func `Int atLeast equality`() {
        #expect(1.atLeast(1) == 1)
    }

    @Test
    func `Int atLeast negative values`() {
        #expect((-5).atLeast(-10) == -5)
        #expect((-15).atLeast(-10) == -10)
    }

    // MARK: - FloatingPoint rounded(toPlaces:)

    @Test
    func `Double rounded to places`() {
        #expect(1.23456.rounded(toPlaces: 2) == 1.23)
        #expect(1.23556.rounded(toPlaces: 2) == 1.24)
    }

    @Test
    func `Double rounded to zero places`() {
        #expect(1.5.rounded(toPlaces: 0) == 2.0)
    }

    @Test
    func `Double rounded to many places`() {
        #expect(1.1.rounded(toPlaces: 10) == 1.1)
    }

    @Test
    func `Double round mutating`() {
        var value = 1.23456
        value.round(toPlaces: 2)
        #expect(value == 1.23)
    }

    // MARK: - String.matches()

    @Test
    func `String matches simple pattern`() {
        #expect("hello world".matches("hello"))
    }

    @Test
    func `String matches regex pattern`() {
        #expect("abc123".matches("[a-z]+\\d+"))
    }

    @Test
    func `String no match returns false`() {
        #expect("abc".matches("\\d+") == false)
    }

    @Test
    func `String matches case insensitive`() {
        #expect("Hello".matches("hello", caseInsensitive: true))
        #expect("Hello".matches("hello") == false)
    }

    // MARK: - String.replacingPattern()

    @Test
    func `String replacingPattern basic`() {
        let result = "hello 123 world".replacingPattern("\\d+", with: "NUM")
        #expect(result == "hello NUM world")
    }

    @Test
    func `String replacingPattern no match`() {
        let result = "hello".replacingPattern("\\d+", with: "NUM")
        #expect(result == "hello")
    }

    @Test
    func `String replacingPattern case insensitive`() {
        let result = "Hello World".replacingPattern("hello", with: "Hi", caseInsensitive: true)
        #expect(result == "Hi World")
    }

    @Test
    func `String replacingPattern invalid regex returns self`() {
        let result = "hello".replacingPattern("[invalid", with: "")
        #expect(result == "hello")
    }

    @Test
    func `String replacingPattern treat as one line`() {
        #expect("a\nb".replacingPattern("a.b", with: "X", treatAsOneLine: true) == "X")
        #expect("a\nb".replacingPattern("a.b", with: "X") == "a\nb")
    }

    @Test
    func `String replacingPattern handles non-BMP characters`() {
        #expect("a👍🏽b".replacingPattern("👍🏽", with: "X") == "aXb")
        #expect("a👍🏽b".replacingPattern("b", with: "Y") == "a👍🏽Y")
        #expect("e\u{301}clair".replacingPattern("e\u{301}", with: "E") == "Eclair")
    }

}
