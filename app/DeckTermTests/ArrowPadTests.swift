import XCTest
@testable import DeckTerm

final class ArrowPadTests: XCTestCase {
    func testStepsAlongTheLongerAxisAndKeepsTheRest() {
        var anchor = CGPoint(x: 100, y: 100)
        XCTAssertEqual(ArrowPad.arrows(from: &anchor, to: CGPoint(x: 60, y: 105)), [.left, .left])
        XCTAssertEqual(anchor, CGPoint(x: 64, y: 105))  // 4 points kept toward the next step
        XCTAssertEqual(ArrowPad.arrows(from: &anchor, to: CGPoint(x: 66, y: 150)), [.down, .down])
        XCTAssertEqual(ArrowPad.arrows(from: &anchor, to: CGPoint(x: 70, y: 140)), [])
        XCTAssertEqual(ArrowPad.arrows(from: &anchor, to: CGPoint(x: 70, y: 100)), [.up, .up])
    }
}
