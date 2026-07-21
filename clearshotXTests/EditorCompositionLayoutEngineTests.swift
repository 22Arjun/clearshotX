import CoreGraphics
import XCTest

@testable import clearshotX

final class EditorCompositionLayoutEngineTests: XCTestCase {
    private let engine = EditorCompositionLayoutEngine()

    func testDisabledCompositionIsIdentityRegardlessOfStoredSettings() {
        var composition = EditorBackgroundComposition.default
        composition.padding = 180
        composition.canvas = .square
        composition.cornerRadius = 48

        let plan = engine.makePlan(
            contentSize: CGSize(width: 800, height: 500),
            composition: composition
        )

        XCTAssertEqual(plan.canvasSize, CGSize(width: 800, height: 500))
        XCTAssertEqual(plan.contentFrame, CGRect(x: 0, y: 0, width: 800, height: 500))
        XCTAssertFalse(plan.isCompositionEnabled)
        XCTAssertEqual(plan.cornerRadius, 0)
        XCTAssertFalse(plan.shadow.isEnabled)
    }

    func testAutomaticCanvasAddsEqualPadding() {
        var composition = enabledComposition()
        composition.padding = 64
        composition.canvas = .automatic

        let plan = engine.makePlan(
            contentSize: CGSize(width: 800, height: 500),
            composition: composition
        )

        XCTAssertEqual(plan.canvasSize.width, 928, accuracy: 0.001)
        XCTAssertEqual(plan.canvasSize.height, 628, accuracy: 0.001)
        assertRect(
            plan.contentFrame,
            equals: CGRect(x: 64, y: 64, width: 800, height: 500)
        )
    }

    func testSquareCanvasExpandsShortAxisWithoutScalingContent() {
        var composition = enabledComposition()
        composition.padding = 50
        composition.canvas = .square

        let plan = engine.makePlan(
            contentSize: CGSize(width: 800, height: 500),
            composition: composition
        )

        XCTAssertEqual(plan.canvasSize, CGSize(width: 900, height: 900))
        assertRect(
            plan.contentFrame,
            equals: CGRect(x: 50, y: 200, width: 800, height: 500)
        )
    }

    func testAlignmentDistributesRatioSpaceInsidePadding() {
        var composition = enabledComposition()
        composition.padding = 40
        composition.canvas = .square
        composition.alignment = .bottomRight

        let plan = engine.makePlan(
            contentSize: CGSize(width: 600, height: 300),
            composition: composition
        )

        XCTAssertEqual(plan.canvasSize, CGSize(width: 680, height: 680))
        assertRect(
            plan.contentFrame,
            equals: CGRect(x: 40, y: 340, width: 600, height: 300)
        )
    }

    func testPortraitRatioExpandsHeight() {
        var composition = enabledComposition()
        composition.padding = 20
        composition.canvas = .portraitFourFive

        let plan = engine.makePlan(
            contentSize: CGSize(width: 600, height: 300),
            composition: composition
        )

        XCTAssertEqual(plan.canvasSize.width, 640, accuracy: 0.001)
        XCTAssertEqual(plan.canvasSize.height, 800, accuracy: 0.001)
        XCTAssertEqual(plan.contentFrame.midX, 320, accuracy: 0.001)
        XCTAssertEqual(plan.contentFrame.midY, 400, accuracy: 0.001)
    }

    func testCornerRadiusIsClampedToContentBounds() {
        var composition = enabledComposition()
        composition.cornerRadius = 96

        let plan = engine.makePlan(
            contentSize: CGSize(width: 100, height: 40),
            composition: composition
        )

        XCTAssertEqual(plan.cornerRadius, 20)
    }

    private func enabledComposition() -> EditorBackgroundComposition {
        var composition = EditorBackgroundComposition.default
        composition.paint = .gradient(.aurora)
        return composition
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}
