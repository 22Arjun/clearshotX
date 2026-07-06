//
//  EditorCanvasResizeService.swift
//  clearshotX
//
//  Created by Codex on 05/07/26.
//

import AppKit
import QuartzCore

@MainActor
protocol EditorCanvasResizing {
    func resizedCanvasImage(from image: NSImage, to cropRect: CGRect) -> NSImage?
}

@MainActor
final class EditorCanvasResizeService: EditorCanvasResizing {
    func resizedCanvasImage(from image: NSImage, to cropRect: CGRect) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let canvasSize = image.editorResizeCanvasSize
        let targetRect = cropRect.standardizedForEditor
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              targetRect.width >= 1,
              targetRect.height >= 1
        else {
            return nil
        }

        let scaleX = CGFloat(sourceImage.width) / canvasSize.width
        let scaleY = CGFloat(sourceImage.height) / canvasSize.height
        let outputPixelSize = CGSize(
            width: max(1, round(targetRect.width * scaleX)),
            height: max(1, round(targetRect.height * scaleY))
        )

        guard let context = CGContext(
            data: nil,
            width: Int(outputPixelSize.width),
            height: Int(outputPixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: targetRect.size)
        rootLayer.bounds = CGRect(origin: .zero, size: targetRect.size)
        rootLayer.masksToBounds = true
        rootLayer.contentsScale = 1

        let imageLayer = CALayer()
        imageLayer.frame = CGRect(
            x: -targetRect.minX,
            y: -targetRect.minY,
            width: canvasSize.width,
            height: canvasSize.height
        )
        imageLayer.contents = sourceImage
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        rootLayer.addSublayer(imageLayer)

        context.interpolationQuality = .high
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: outputPixelSize))

        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        rootLayer.render(in: context)
        context.restoreGState()

        guard let resizedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: resizedImage, size: targetRect.size)
    }
}

private extension NSImage {
    var editorResizeCanvasSize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSSize(width: 960, height: 540)
        }

        return NSSize(width: cgImage.width, height: cgImage.height)
    }
}
