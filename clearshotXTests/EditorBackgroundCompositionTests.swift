import AppKit
import CoreGraphics
import XCTest

@testable import clearshotX

final class EditorBackgroundCompositionCodableTests: XCTestCase {
    func testCompositionRoundTripsWithVersionedValueTypes() throws {
        var composition = EditorBackgroundComposition.default
        composition.paint = .gradient(.ultraviolet)
        composition.canvas = .portraitFourFive
        composition.padding = 88
        composition.alignment = .topRight
        composition.cornerRadius = 22
        composition.shadow.opacity = 0.42

        let data = try JSONEncoder().encode(composition)
        let decoded = try JSONDecoder().decode(EditorBackgroundComposition.self, from: data)

        XCTAssertEqual(decoded, composition)
        XCTAssertEqual(decoded.version, EditorBackgroundComposition.schemaVersion)
    }
}

@MainActor
final class EditorBackgroundViewModelTests: XCTestCase {
    func testBackgroundMutationParticipatesInUndoAndRedo() {
        let viewModel = EditorViewModel(image: makeImage(pixelSize: CGSize(width: 80, height: 40)))

        viewModel.setBackgroundPaint(.gradient(.aurora))
        XCTAssertEqual(viewModel.backgroundComposition.paint, .gradient(.aurora))
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undo()
        XCTAssertEqual(viewModel.backgroundComposition.paint, .none)
        XCTAssertTrue(viewModel.canRedo)

        viewModel.redo()
        XCTAssertEqual(viewModel.backgroundComposition.paint, .gradient(.aurora))
    }

    func testContinuousPaddingEditCreatesSingleUndoTransition() {
        let viewModel = EditorViewModel(image: makeImage(pixelSize: CGSize(width: 80, height: 40)))
        viewModel.setBackgroundPaint(.solid(.indigo))

        viewModel.beginBackgroundContinuousEditing()
        viewModel.setBackgroundPadding(80)
        viewModel.setBackgroundPadding(96)
        viewModel.setBackgroundPadding(112)
        viewModel.endBackgroundContinuousEditing()

        XCTAssertEqual(viewModel.backgroundComposition.padding, 112)
        viewModel.undo()
        XCTAssertEqual(viewModel.backgroundComposition.padding, 64)
        XCTAssertEqual(viewModel.backgroundComposition.paint, .solid(.indigo))
    }
}

@MainActor
final class EditorBackgroundRendererTests: XCTestCase {
    private let renderer = EditorFlattenedImageRenderer()

    func testDisabledCompositionPreservesNativePixelDimensions() throws {
        let image = makeImage(
            pixelSize: CGSize(width: 200, height: 100),
            logicalSize: CGSize(width: 100, height: 50),
            color: .systemBlue
        )

        let rendered = try XCTUnwrap(renderer.render(
            image: image,
            annotations: [],
            composition: .default
        ))
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(cgImage.width, 200)
        XCTAssertEqual(cgImage.height, 100)
        XCTAssertEqual(rendered.size, CGSize(width: 100, height: 50))
    }

    func testAutomaticBackgroundExpandsAtNativeRetinaScale() throws {
        let image = makeImage(
            pixelSize: CGSize(width: 200, height: 100),
            logicalSize: CGSize(width: 100, height: 50),
            color: .systemBlue
        )
        var composition = EditorBackgroundComposition.default
        composition.paint = .solid(.coral)
        composition.padding = 10
        composition.shadow = .none

        let rendered = try XCTUnwrap(renderer.render(
            image: image,
            annotations: [],
            composition: composition
        ))
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(cgImage.width, 240)
        XCTAssertEqual(cgImage.height, 140)
        XCTAssertEqual(rendered.size, CGSize(width: 120, height: 70))
    }

    func testSolidBackgroundAndContentBothReachExport() throws {
        let image = makeImage(
            pixelSize: CGSize(width: 40, height: 20),
            color: .systemBlue
        )
        var composition = EditorBackgroundComposition.default
        composition.paint = .solid(.coral)
        composition.padding = 10
        composition.cornerRadius = 0
        composition.shadow = .none

        let rendered = try XCTUnwrap(renderer.render(
            image: image,
            annotations: [],
            composition: composition
        ))
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sampler = try PixelSampler(image: cgImage)

        let background = sampler.color(x: 2, y: 2)
        let content = sampler.color(x: cgImage.width / 2, y: cgImage.height / 2)

        XCTAssertGreaterThan(background.red, background.blue)
        XCTAssertGreaterThan(content.blue, content.red)
    }

    func testSquareCanvasExportHasExactAspectRatio() throws {
        let image = makeImage(pixelSize: CGSize(width: 120, height: 60), color: .systemGreen)
        var composition = EditorBackgroundComposition.default
        composition.paint = .gradient(.lagoon)
        composition.canvas = .square
        composition.padding = 12
        composition.shadow = .none

        let rendered = try XCTUnwrap(renderer.render(
            image: image,
            annotations: [],
            composition: composition
        ))
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(cgImage.width, cgImage.height)
        XCTAssertEqual(rendered.size.width, rendered.size.height, accuracy: 0.001)
    }

    func testTopAlignmentUsesTheSameTopOriginSemanticsAsEditorPreview() throws {
        let image = makeImage(pixelSize: CGSize(width: 40, height: 20), color: .systemBlue)
        var composition = EditorBackgroundComposition.default
        composition.paint = .solid(.coral)
        composition.canvas = .square
        composition.padding = 10
        composition.alignment = .top
        composition.cornerRadius = 0
        composition.shadow = .none

        let rendered = try XCTUnwrap(renderer.render(
            image: image,
            annotations: [],
            composition: composition
        ))
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sampler = try PixelSampler(image: cgImage)

        // PixelSampler reads Core Graphics rows from the bottom. A top-aligned
        // 20px image in a 60px canvas should therefore occupy rows 30...49.
        let nearTop = sampler.color(x: 30, y: 45)
        let nearBottom = sampler.color(x: 30, y: 15)

        XCTAssertGreaterThan(nearTop.blue, nearTop.red)
        XCTAssertGreaterThan(nearBottom.red, nearBottom.blue)
    }
}

private func makeImage(
    pixelSize: CGSize,
    logicalSize: CGSize? = nil,
    color: NSColor = .white
) -> NSImage {
    let width = max(1, Int(pixelSize.width))
    let height = max(1, Int(pixelSize.height))
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let cgImage = context.makeImage()!
    return NSImage(cgImage: cgImage, size: logicalSize ?? pixelSize)
}

private struct PixelSampler {
    struct Color {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    private let width: Int
    private let height: Int
    private let bytes: [UInt8]

    init(image: CGImage) throws {
        width = image.width
        height = image.height
        var storage = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else {
            throw CocoaError(.coderInvalidValue)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = storage
    }

    func color(x: Int, y: Int) -> Color {
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)
        let index = (clampedY * width + clampedX) * 4
        return Color(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2])
    }
}
