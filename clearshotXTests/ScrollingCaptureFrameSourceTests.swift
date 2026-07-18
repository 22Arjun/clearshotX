import CoreGraphics
import ScreenCaptureKit
import XCTest

@testable import clearshotX

final class ScrollingCaptureRegionResolverTests: XCTestCase {
    func testConvertsAppKitGlobalRegionToDisplayLocalTopLeftCoordinates() throws {
        let display = ScrollingCaptureDisplayDescriptor(
            displayID: 42,
            frame: CGRect(x: 1_000, y: -200, width: 800, height: 600),
            pointPixelScale: 2
        )

        let geometry = try ScrollingCaptureRegionResolver.resolve(
            selectedRegion: CGRect(x: 1_100, y: 0, width: 300, height: 150),
            displays: [display]
        )

        XCTAssertEqual(geometry.displayID, 42)
        XCTAssertEqual(geometry.sourceRect, CGRect(x: 100, y: 250, width: 300, height: 150))
        XCTAssertEqual(geometry.globalRect, CGRect(x: 1_100, y: 0, width: 300, height: 150))
        XCTAssertEqual(geometry.pixelWidth, 600)
        XCTAssertEqual(geometry.pixelHeight, 300)
    }

    func testPixelAlignsFractionalRetinaSelectionOutward() throws {
        let display = ScrollingCaptureDisplayDescriptor(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            pointPixelScale: 2
        )

        let geometry = try ScrollingCaptureRegionResolver.resolve(
            selectedRegion: CGRect(x: 10.2, y: 20.2, width: 100.1, height: 80.1),
            displays: [display]
        )

        XCTAssertEqual(geometry.sourceRect.minX, 10, accuracy: 0.001)
        XCTAssertEqual(geometry.sourceRect.maxX, 110.5, accuracy: 0.001)
        XCTAssertEqual(geometry.sourceRect.minY, 499.5, accuracy: 0.001)
        XCTAssertEqual(geometry.sourceRect.maxY, 580, accuracy: 0.001)
        XCTAssertEqual(geometry.pixelWidth, 201)
        XCTAssertEqual(geometry.pixelHeight, 161)
    }

    func testRejectsSelectionSpanningDisplays() {
        let displays = [
            ScrollingCaptureDisplayDescriptor(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                pointPixelScale: 1
            ),
            ScrollingCaptureDisplayDescriptor(
                displayID: 2,
                frame: CGRect(x: 800, y: 0, width: 800, height: 600),
                pointPixelScale: 2
            ),
        ]

        XCTAssertThrowsError(
            try ScrollingCaptureRegionResolver.resolve(
                selectedRegion: CGRect(x: 700, y: 100, width: 200, height: 300),
                displays: displays
            )
        ) { error in
            XCTAssertEqual(
                error as? ScrollingCaptureFrameSourceError,
                .regionSpansMultipleDisplays
            )
        }
    }
}

final class ScrollingCaptureFrameGateTests: XCTestCase {
    func testAcceptsOnlyCompleteExpectedSizeFrames() {
        XCTAssertTrue(
            ScrollingCaptureFrameGate.shouldProcess(
                status: .complete,
                pixelWidth: 600,
                pixelHeight: 400,
                expectedWidth: 600,
                expectedHeight: 400
            )
        )
        XCTAssertFalse(
            ScrollingCaptureFrameGate.shouldProcess(
                status: .idle,
                pixelWidth: 600,
                pixelHeight: 400,
                expectedWidth: 600,
                expectedHeight: 400
            )
        )
        XCTAssertFalse(
            ScrollingCaptureFrameGate.shouldProcess(
                status: .complete,
                pixelWidth: 599,
                pixelHeight: 400,
                expectedWidth: 600,
                expectedHeight: 400
            )
        )
    }
}

final class LatestValueProcessorTests: XCTestCase {
    func testBusyProcessorDropsStalePendingValues() {
        let startedFirst = expectation(description: "Started first value")
        let processedLatest = expectation(description: "Processed latest value")
        let releaseFirst = DispatchSemaphore(value: 0)
        let processed = LockedValues<Int>()

        let processor = LatestValueProcessor<Int>(
            queue: DispatchQueue(label: "LatestValueProcessorTests")
        ) { value in
            processed.append(value)

            if value == 1 {
                startedFirst.fulfill()
                _ = releaseFirst.wait(timeout: .now() + 2)
            } else if value == 3 {
                processedLatest.fulfill()
            }
        }

        processor.submit(1)
        wait(for: [startedFirst], timeout: 2)
        processor.submit(2)
        processor.submit(3)
        releaseFirst.signal()
        wait(for: [processedLatest], timeout: 2)

        XCTAssertEqual(processed.snapshot(), [1, 3])
    }
}

private nonisolated final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
