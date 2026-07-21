//
//  EditorOutputService.swift
//  clearshotX
//
//  Created by Codex on 05/07/26.
//

import AppKit

@MainActor
protocol EditorOutputServicing {
    @discardableResult
    func copy(
        image: NSImage,
        annotations: [AnnotationObject],
        composition: EditorBackgroundComposition
    ) -> Bool

    func save(
        image: NSImage,
        sourceFileURL: URL?,
        annotations: [AnnotationObject],
        composition: EditorBackgroundComposition
    )
}

@MainActor
final class EditorOutputService: EditorOutputServicing {
    private let clipboardService: ClipboardService
    private let flattenedImageRenderer: EditorFlattenedImageRendering
    private let captureExportService: CaptureExportServicing

    init(
        clipboardService: ClipboardService? = nil,
        flattenedImageRenderer: EditorFlattenedImageRendering? = nil,
        captureExportService: CaptureExportServicing? = nil
    ) {
        self.clipboardService = clipboardService ?? ClipboardService()
        self.flattenedImageRenderer = flattenedImageRenderer ?? EditorFlattenedImageRenderer()
        self.captureExportService = captureExportService ?? CaptureExportService()
    }

    @discardableResult
    func copy(
        image: NSImage,
        annotations: [AnnotationObject],
        composition: EditorBackgroundComposition
    ) -> Bool {
        guard let flattenedImage = flattenedImageRenderer.render(
            image: image,
            annotations: annotations,
            composition: composition
        ) else {
            NSSound.beep()
            return false
        }

        return clipboardService.copy(flattenedImage)
    }

    func save(
        image: NSImage,
        sourceFileURL: URL?,
        annotations: [AnnotationObject],
        composition: EditorBackgroundComposition
    ) {
        guard let flattenedImage = flattenedImageRenderer.render(
            image: image,
            annotations: annotations,
            composition: composition
        ),
              let pngData = flattenedImage.pngData()
        else {
            NSSound.beep()
            return
        }

        captureExportService.savePNGData(
            pngData,
            suggestedFileName: defaultFileName(sourceFileURL: sourceFileURL)
        ) { result in
            if case let .failure(error) = result {
                Self.presentSaveError(error)
            }
        }
    }

    private func defaultFileName(sourceFileURL: URL?) -> String {
        let fallbackName = "Annotated Screenshot"
        let baseName = sourceFileURL?.deletingPathExtension().lastPathComponent ?? fallbackName

        if baseName.localizedCaseInsensitiveContains("annotated") {
            return "\(baseName).png"
        }

        return "\(baseName)-annotated.png"
    }

    private static func presentSaveError(_ error: CaptureExportError) {
        let alert = NSAlert(error: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
protocol EditorFlattenedImageRendering {
    func render(
        image: NSImage,
        annotations: [AnnotationObject],
        composition: EditorBackgroundComposition
    ) -> NSImage?
}

@MainActor
final class EditorFlattenedImageRenderer: EditorFlattenedImageRendering {
    private let annotationLayerRenderer = AnnotationLayerRenderer()
    private let compositionLayoutEngine = EditorCompositionLayoutEngine()

    func render(
        image: NSImage,
        annotations: [AnnotationObject],
        composition: EditorBackgroundComposition
    ) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let canvasSize = image.editorExportCanvasSize
        guard canvasSize.width > 0,
              canvasSize.height > 0
        else {
            return nil
        }

        let plan = compositionLayoutEngine.makePlan(
            contentSize: canvasSize,
            composition: composition
        )
        let pixelScale = max(
            1,
            CGFloat(sourceImage.width) / canvasSize.width,
            CGFloat(sourceImage.height) / canvasSize.height
        )
        let outputSize = CGSize(
            width: max(1, round(plan.canvasSize.width * pixelScale)),
            height: max(1, round(plan.canvasSize.height * pixelScale))
        )
        guard let context = CGContext(
            data: nil,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rootLayer = makeLayerTree(
            sourceImage: sourceImage,
            canvasSize: canvasSize,
            annotations: annotations,
            plan: plan
        )
        let scaleX = outputSize.width / plan.canvasSize.width
        let scaleY = outputSize.height / plan.canvasSize.height

        context.interpolationQuality = .high
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: outputSize))

        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        rootLayer.render(in: context)
        context.restoreGState()

        guard let flattenedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: flattenedImage, size: plan.canvasSize)
    }

    private func makeLayerTree(
        sourceImage: CGImage,
        canvasSize: CGSize,
        annotations: [AnnotationObject],
        plan: EditorCompositionRenderPlan
    ) -> CALayer {
        let rootLayer = CALayer()
        rootLayer.frame = plan.canvasBounds
        rootLayer.bounds = plan.canvasBounds
        rootLayer.contentsScale = 1
        rootLayer.masksToBounds = true

        if let backgroundLayer = makeBackgroundLayer(for: plan) {
            rootLayer.addSublayer(backgroundLayer)
        }

        let contentPresentationLayer = CALayer()
        contentPresentationLayer.frame = plan.contentFrame
        contentPresentationLayer.bounds = CGRect(origin: .zero, size: canvasSize)
        contentPresentationLayer.contentsScale = 1
        contentPresentationLayer.masksToBounds = false

        if plan.isCompositionEnabled,
           plan.shadow.isEnabled,
           plan.shadow.opacity > 0 {
            contentPresentationLayer.shadowColor = NSColor.black.cgColor
            contentPresentationLayer.shadowOpacity = Float(plan.shadow.opacity)
            contentPresentationLayer.shadowRadius = plan.shadow.radius
            contentPresentationLayer.shadowOffset = CGSize(
                width: plan.shadow.offsetX,
                height: plan.shadow.offsetY
            )
            contentPresentationLayer.shadowPath = CGPath(
                roundedRect: contentPresentationLayer.bounds,
                cornerWidth: plan.cornerRadius,
                cornerHeight: plan.cornerRadius,
                transform: nil
            )
        }

        let contentClipLayer = CALayer()
        contentClipLayer.frame = contentPresentationLayer.bounds
        contentClipLayer.bounds = contentPresentationLayer.bounds
        contentClipLayer.contentsScale = 1
        contentClipLayer.cornerRadius = plan.cornerRadius
        contentClipLayer.masksToBounds = plan.cornerRadius > 0

        let imageLayer = CALayer()
        imageLayer.frame = contentClipLayer.bounds
        imageLayer.contents = sourceImage
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        contentClipLayer.addSublayer(imageLayer)

        let annotationContainerLayer = CALayer()
        annotationContainerLayer.frame = contentClipLayer.bounds
        annotationContainerLayer.masksToBounds = true
        annotationContainerLayer.contentsScale = 1
        contentClipLayer.addSublayer(annotationContainerLayer)

        annotationLayerRenderer.render(
            annotations: annotations,
            draftAnnotation: nil,
            selectedAnnotationID: nil,
            sourceImage: sourceImage,
            in: annotationContainerLayer,
            contentsScale: 1,
            selectionHandleSize: 0
        )

        contentPresentationLayer.addSublayer(contentClipLayer)
        rootLayer.addSublayer(contentPresentationLayer)

        return rootLayer
    }

    private func makeBackgroundLayer(
        for plan: EditorCompositionRenderPlan
    ) -> CALayer? {
        switch plan.paint {
        case .none:
            return nil
        case let .solid(solidColor):
            let layer = CALayer()
            layer.frame = plan.canvasBounds
            layer.backgroundColor = solidColor.color.cgColor
            layer.contentsScale = 1
            return layer
        case let .gradient(gradient):
            let layer = CAGradientLayer()
            layer.frame = plan.canvasBounds
            layer.colors = gradient.colors.map(\.cgColor)
            layer.locations = gradient.colors.indices.map { index in
                NSNumber(value: Double(index) / Double(max(1, gradient.colors.count - 1)))
            }
            layer.startPoint = gradient.startPoint
            layer.endPoint = gradient.endPoint
            layer.contentsScale = 1
            return layer
        }
    }
}

private extension NSImage {
    var editorExportCanvasSize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSSize(width: 960, height: 540)
        }

        return NSSize(width: cgImage.width, height: cgImage.height)
    }

    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        bitmapRepresentation.size = size
        return bitmapRepresentation.representation(using: .png, properties: [:])
    }
}
