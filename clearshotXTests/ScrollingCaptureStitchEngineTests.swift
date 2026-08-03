import CoreGraphics
import Foundation
import XCTest

@testable import clearshotX

final class ScrollingCaptureStitchEngineTests: XCTestCase {
    func testFindsExactNativeOffsetAfterReducedCoarseSearch() throws {
        let document = stitchDocument(width: 240, height: 900)
        let previous = try stitchCrop(document, y: 31, height: 320)
        let current = try stitchCrop(document, y: 104, height: 320)
        var configuration = stitchConfiguration()
        configuration.maximumCoarseWidth = 80
        configuration.maximumCoarseHeight = 96
        configuration.nativeRefinementWidth = 128
        let engine = ScrollingCaptureStitchEngine(configuration: configuration)

        let match = try engine.match(previous: previous, current: current)

        XCTAssertEqual(match.verticalOffset, 73)
        XCTAssertGreaterThan(match.correlation, 0.98)
        XCTAssertGreaterThan(match.peakMargin, 0.10)
        XCTAssertEqual(match.disposition, .accept)
    }

    func testSparsePageUsesTexturedBandsAroundBlankCenter() throws {
        let document = sparseStitchDocument(width: 220, height: 860)
        let previous = try stitchCrop(document, y: 0, height: 320)
        let current = try stitchCrop(document, y: 74, height: 320)
        var configuration = stitchConfiguration()
        configuration.preferredCorrelationBandHeight = 54
        configuration.nativeRefinementBandHeight = 54
        configuration.maximumCorrelationBands = 5
        let engine = ScrollingCaptureStitchEngine(configuration: configuration)

        let match = try engine.match(previous: previous, current: current)

        XCTAssertEqual(match.verticalOffset, 74)
        XCTAssertGreaterThan(match.correlation, 0.85)
        XCTAssertEqual(match.disposition, .accept)
    }

    func testWideViewportRetainsEnoughHorizontalEvidenceForReliableAlignment() throws {
        let document = stitchDocument(width: 1_920, height: 1_120)
        let previous = try stitchCrop(document, y: 48, height: 520)
        let current = try stitchCrop(document, y: 174, height: 520)
        var configuration = stitchConfiguration()
        configuration.maximumCoarseWidth = 96
        configuration.nativeRefinementWidth = 96
        configuration.maximumWideCoarseWidth = 384
        configuration.maximumWideNativeRefinementWidth = 320
        let engine = ScrollingCaptureStitchEngine(configuration: configuration)

        let match = try engine.match(previous: previous, current: current)

        XCTAssertEqual(match.verticalOffset, 126)
        XCTAssertEqual(match.disposition, .accept)
        XCTAssertGreaterThan(match.correlation, 0.98)
    }

    func testIdenticalFramesProduceReliableStationaryCandidate() throws {
        let frame = try stitchCrop(
            stitchDocument(width: 180, height: 420),
            y: 50,
            height: 260
        )
        let engine = ScrollingCaptureStitchEngine(configuration: stitchConfiguration())

        let match = try engine.match(previous: frame, current: frame)

        XCTAssertEqual(match.verticalOffset, 0)
        XCTAssertEqual(match.correlation, 1, accuracy: 0.000_1)
        XCTAssertTrue(match.isStationary)
        XCTAssertTrue(match.isReliable)
    }

    func testStationaryEndFrameCompletesWithoutDependingOnCoarseOverlapSearch() throws {
        let frame = try stitchCrop(
            sparseStitchDocument(width: 180, height: 420),
            y: 50,
            height: 260
        )
        var configuration = stitchConfiguration()
        // Deliberately too little coarse vertical information to register a
        // sparse page reliably. A real page end must still be recognized as a
        // normal stationary completion rather than an overlap failure.
        configuration.maximumCoarseHeight = 2
        let engine = ScrollingCaptureStitchEngine(configuration: configuration)

        let match = try engine.match(previous: frame, current: frame)

        XCTAssertEqual(match.disposition, .stationary)
        XCTAssertEqual(match.verticalOffset, 0)
    }

    func testUnrelatedFramesRequestSmallerDeltaInsteadOfInventingReliableOffset() throws {
        let previous = stitchImage(width: 180, height: 260) { x, y in
            UInt8((x &* 17 &+ y &* 43 &+ (x * y) % 97) % 256)
        }
        let current = stitchImage(width: 180, height: 260) { x, y in
            UInt8((x &* 61 &+ y &* 11 &+ ((x + 13) * (y + 7)) % 181) % 256)
        }
        let engine = ScrollingCaptureStitchEngine(configuration: stitchConfiguration())

        let match = try engine.match(previous: previous, current: current)

        XCTAssertEqual(match.disposition, .retryWithSmallerScrollDelta)
        XCTAssertFalse(match.isReliable)
        XCTAssertLessThan(match.correlation, 0.85)
    }

    func testRepeatedRowsAreLowConfidenceEvenWhenOneOffsetCorrelatesPerfectly() throws {
        let document = stitchImage(width: 180, height: 700) { x, y in
            let repeatedRow = y % 16
            return UInt8((repeatedRow &* 37 &+ x &* 23 &+ (x / 9) &* 71) % 256)
        }
        let previous = try stitchCrop(document, y: 0, height: 280)
        let current = try stitchCrop(document, y: 37, height: 280)
        let engine = ScrollingCaptureStitchEngine(configuration: stitchConfiguration())

        let match = try engine.match(previous: previous, current: current)

        XCTAssertEqual(match.disposition, .retryWithSmallerScrollDelta)
        XCTAssertLessThan(match.peakMargin, 0.012)
    }

    func testDetectsPaddedStickyHeaderAndFooterWithoutChangingOffset() throws {
        let document = stitchDocument(width: 200, height: 900)
        let previous = stickyViewport(
            document: document,
            documentOffset: 10,
            height: 300,
            header: 28,
            footer: 20
        )
        let current = stickyViewport(
            document: document,
            documentOffset: 79,
            height: 300,
            header: 28,
            footer: 20
        )
        let engine = ScrollingCaptureStitchEngine(configuration: stitchConfiguration())

        let match = try engine.match(previous: previous, current: current)

        XCTAssertEqual(match.verticalOffset, 69)
        XCTAssertEqual(match.disposition, .accept)
        XCTAssertEqual(match.detectedContentInsets.top, 28, accuracy: 2)
        XCTAssertEqual(match.detectedContentInsets.bottom, 20, accuracy: 2)
    }

    func testExplicitInsetsAreNeverReducedByAutomaticDetection() throws {
        let document = stitchDocument(width: 180, height: 700)
        let previous = stickyViewport(
            document: document,
            documentOffset: 0,
            height: 260,
            header: 18,
            footer: 14
        )
        let current = stickyViewport(
            document: document,
            documentOffset: 61,
            height: 260,
            header: 18,
            footer: 14
        )
        var configuration = stitchConfiguration()
        configuration.contentInsets = ScrollingCaptureContentInsets(top: 20, bottom: 16)
        let engine = ScrollingCaptureStitchEngine(configuration: configuration)

        let match = try engine.match(previous: previous, current: current)

        XCTAssertEqual(match.verticalOffset, 61)
        XCTAssertGreaterThanOrEqual(match.detectedContentInsets.top, 20)
        XCTAssertGreaterThanOrEqual(match.detectedContentInsets.bottom, 16)
    }

    func testRejectsMismatchedNativeFrameDimensions() throws {
        let engine = ScrollingCaptureStitchEngine(configuration: stitchConfiguration())
        let previous = stitchDocument(width: 100, height: 180)
        let current = stitchDocument(width: 101, height: 180)

        XCTAssertThrowsError(try engine.match(previous: previous, current: current)) {
            XCTAssertEqual(
                $0 as? ScrollingCaptureStitchError,
                .inconsistentFrameSize
            )
        }
    }

    func testAutoLoopAppendsNativeRowsAndStopsAfterTwoStationarySteps() async throws {
        let document = stitchDocument(width: 180, height: 700)
        let first = try stitchCrop(document, y: 0, height: 260)
        let advanced = try stitchCrop(document, y: 61, height: 260)
        let source = ScriptedDiscreteFrameSource(
            frames: [first, advanced, advanced, advanced]
        )
        let driver = RecordingScrollDriver()
        let controller = makeAutoController(source: source, driver: driver)
        let completed = expectation(description: "Automatic capture reached page end")

        _ = try await controller.start(
            selectedRegion: CGRect(x: 10, y: 20, width: 180, height: 260),
            onProgress: { _ in },
            onPreview: { _ in },
            onCompletion: { result in
                guard case let .success(image?) = result else {
                    XCTFail("Expected a completed native image")
                    return completed.fulfill()
                }
                XCTAssertEqual(image.width, 180)
                XCTAssertEqual(image.height, 321)
                completed.fulfill()
            }
        )

        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(driver.deltas.count, 3)
        XCTAssertTrue(driver.deltas.allSatisfy { $0 > 0 })
        XCTAssertEqual(source.stopCount, 1)
    }

    func testAutoLoopResamplesLowConfidenceFrameWithoutReverseScrolling() async throws {
        let document = stitchDocument(width: 180, height: 700)
        let first = try stitchCrop(document, y: 0, height: 260)
        let unrelated = stitchImage(width: 180, height: 260) { x, y in
            UInt8((x &* 71 &+ y &* 13 &+ ((x + 9) * (y + 3)) % 193) % 256)
        }
        let advanced = try stitchCrop(document, y: 61, height: 260)
        let source = ScriptedDiscreteFrameSource(
            frames: [first, unrelated, first, advanced, advanced, advanced]
        )
        let driver = RecordingScrollDriver()
        let controller = makeAutoController(source: source, driver: driver)
        let completed = expectation(description: "In-place recovery completed")

        _ = try await controller.start(
            selectedRegion: CGRect(x: 0, y: 0, width: 180, height: 260),
            onProgress: { _ in },
            onPreview: { _ in },
            onCompletion: { result in
                guard case let .success(image?) = result else {
                    XCTFail("Expected in-place recovery to complete")
                    return completed.fulfill()
                }
                XCTAssertEqual(image.height, 321)
                completed.fulfill()
            }
        )

        await fulfillment(of: [completed], timeout: 2)
        let deltas = driver.deltas
        XCTAssertGreaterThanOrEqual(deltas.count, 4)
        XCTAssertTrue(deltas.allSatisfy { $0 > 0 })
    }

    func testAutoLoopFinishesVerifiedPrefixWhenViewportNeverRegisters() async throws {
        let first = try stitchCrop(
            stitchDocument(width: 180, height: 700),
            y: 0,
            height: 260
        )
        let unrelated = stitchImage(width: 180, height: 260) { x, y in
            UInt8((x &* 71 &+ y &* 13 &+ ((x + 9) * (y + 3)) % 193) % 256)
        }
        let source = ScriptedDiscreteFrameSource(frames: [first, unrelated])
        let driver = RecordingScrollDriver()
        let controller = makeAutoController(source: source, driver: driver)
        let completed = expectation(description: "Verified prefix completed")

        _ = try await controller.start(
            selectedRegion: CGRect(x: 0, y: 0, width: 180, height: 260),
            onProgress: { _ in },
            onPreview: { _ in },
            onCompletion: { result in
                guard case let .success(image?) = result else {
                    XCTFail("Expected a safe partial capture, not an error")
                    return completed.fulfill()
                }
                XCTAssertEqual(image.width, 180)
                XCTAssertEqual(image.height, 260)
                completed.fulfill()
            }
        )

        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(driver.deltas.count, 1)
        XCTAssertTrue(driver.deltas.allSatisfy { $0 > 0 })
    }

    func testAutoScrollBreaksAReadableStepIntoSmallContinuousPulses() async throws {
        let document = stitchDocument(width: 180, height: 700)
        let first = try stitchCrop(document, y: 0, height: 260)
        let advanced = try stitchCrop(document, y: 61, height: 260)
        let source = ScriptedDiscreteFrameSource(
            frames: [first, advanced, advanced, advanced]
        )
        let driver = RecordingScrollDriver()
        var autoConfiguration = ScrollingCaptureAutoCaptureConfiguration()
        autoConfiguration.viewportStepFraction = 0.25 // 65 points for this viewport
        autoConfiguration.maximumPulsePoints = 20
        autoConfiguration.pulseInterval = .zero
        autoConfiguration.readableStepPause = .zero
        autoConfiguration.initialSettleDelay = .zero
        autoConfiguration.settleProbeDelay = .zero
        autoConfiguration.maximumSettleProbes = 0
        autoConfiguration.stationaryStepsToFinish = 2
        let controller = ScrollingCaptureAutoCaptureController(
            frameSource: source,
            scrollDriver: driver,
            stitchEngine: ScrollingCaptureStitchEngine(configuration: stitchConfiguration()),
            autoConfiguration: autoConfiguration
        )
        let completed = expectation(description: "Smooth automatic capture completed")

        _ = try await controller.start(
            selectedRegion: CGRect(x: 0, y: 0, width: 180, height: 260),
            onProgress: { _ in },
            onPreview: { _ in },
            onCompletion: { result in
                guard case .success = result else {
                    XCTFail("Expected a completed capture")
                    return completed.fulfill()
                }
                completed.fulfill()
            }
        )

        await fulfillment(of: [completed], timeout: 2)
        let firstStep = Array(driver.deltas.prefix(4))
        XCTAssertEqual(firstStep.count, 4)
        XCTAssertEqual(firstStep.reduce(0, +), 65)
        XCTAssertTrue(firstStep.allSatisfy { $0 > 0 && $0 <= 20 })
    }
}

private func makeAutoController(
    source: ScriptedDiscreteFrameSource,
    driver: RecordingScrollDriver
) -> ScrollingCaptureAutoCaptureController {
    var autoConfiguration = ScrollingCaptureAutoCaptureConfiguration()
    autoConfiguration.initialSettleDelay = .zero
    autoConfiguration.settleProbeDelay = .zero
    autoConfiguration.alignmentRecoveryDelay = .zero
    autoConfiguration.maximumSettleProbes = 0
    // The existing capture-loop tests exercise registration behavior, not the
    // user-facing pacing layer. One pulse keeps their scroll-event assertions
    // focused and deterministic.
    autoConfiguration.maximumPulsePoints = .max
    autoConfiguration.pulseInterval = .zero
    autoConfiguration.readableStepPause = .zero
    autoConfiguration.stationaryStepsToFinish = 2
    return ScrollingCaptureAutoCaptureController(
        frameSource: source,
        scrollDriver: driver,
        stitchEngine: ScrollingCaptureStitchEngine(configuration: stitchConfiguration()),
        autoConfiguration: autoConfiguration
    )
}

private final class ScriptedDiscreteFrameSource:
    ScrollingCaptureDiscreteFrameSourcing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let frames: [CGImage]
    private var nextIndex = 0
    private var stops = 0

    init(frames: [CGImage]) {
        self.frames = frames
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    func prepare(selectedRegion: CGRect) async throws -> ScrollingCaptureRegionGeometry {
        ScrollingCaptureRegionGeometry(
            displayID: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            globalRect: selectedRegion,
            sourceRect: selectedRegion,
            pointPixelScale: 1,
            pixelWidth: frames[0].width,
            pixelHeight: frames[0].height
        )
    }

    func captureFrame() async throws -> CGImage {
        nextFrame()
    }

    func stop() async {
        recordStop()
    }

    private func nextFrame() -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        let index = min(nextIndex, frames.count - 1)
        nextIndex += 1
        return frames[index]
    }

    private func recordStop() {
        lock.lock()
        stops += 1
        lock.unlock()
    }
}

private final class RecordingScrollDriver:
    ScrollingCaptureScrollDriving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedDeltas: [Int] = []

    var deltas: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedDeltas
    }

    func scroll(verticalDelta: Int, at appKitPoint: CGPoint) throws {
        lock.lock()
        recordedDeltas.append(verticalDelta)
        lock.unlock()
    }
}

private func stitchConfiguration() -> ScrollingCaptureStitchConfiguration {
    var configuration = ScrollingCaptureStitchConfiguration()
    configuration.maximumCoarseWidth = 128
    configuration.maximumCoarseHeight = 240
    configuration.nativeRefinementWidth = 128
    configuration.preferredCorrelationBandHeight = 100
    configuration.nativeRefinementBandHeight = 180
    configuration.nativeRefinementRadius = 8
    configuration.minimumOverlapFraction = 0.30
    configuration.maximumScrollFraction = 0.65
    configuration.correlationThreshold = 0.85
    configuration.minimumPeakMargin = 0.012
    return configuration
}

private func stitchDocument(width: Int, height: Int) -> CGImage {
    stitchImage(width: width, height: height) { x, y in
        UInt8(
            (y &* 47
                &+ x &* 29
                &+ (y / 7) &* 83
                &+ (x / 5) &* 31
                &+ ((x * y) / 19) &* 13) % 256
        )
    }
}

private func sparseStitchDocument(width: Int, height: Int) -> CGImage {
    stitchImage(width: width, height: height) { x, y in
        let inTextBand = (y % 190) < 44 || (y % 190) > 154
        guard inTextBand else { return 248 }
        if x % 17 < 11 || (x + y / 3) % 29 < 13 {
            return UInt8((53 &+ x &* 19 &+ y &* 7 &+ (x / 5) &* 31) % 196)
        }
        return 246
    }
}

private func stickyViewport(
    document: CGImage,
    documentOffset: Int,
    height: Int,
    header: Int,
    footer: Int
) -> CGImage {
    let pixels = stitchGrayPixels(document)
    return stitchImage(width: document.width, height: height) { x, y in
        if y < header {
            // Blank outer padding followed by stable navigation detail.
            if y < 6 { return 246 }
            return UInt8((31 &+ x &* 17 &+ y &* 11) % 220)
        }
        if y >= height - footer {
            if y >= height - 5 { return 18 }
            return UInt8((193 &+ x &* 7 &+ y &* 19) % 230)
        }
        let sourceY = documentOffset + y - header
        return pixels[sourceY * document.width + x]
    }
}

private func stitchCrop(_ image: CGImage, y: Int, height: Int) throws -> CGImage {
    try XCTUnwrap(
        image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: height))
    )
}

private func stitchImage(
    width: Int,
    height: Int,
    value: (Int, Int) -> UInt8
) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let component = value(x, y)
            let offset = (y * width + x) * 4
            bytes[offset] = component
            bytes[offset + 1] = component
            bytes[offset + 2] = component
        }
    }
    let data = Data(bytes)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func stitchGrayPixels(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
}
