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
    func resizedCanvasImage(from image: NSImage, to cropRect: CGRect, fillColor: NSColor) -> NSImage?
    func rotatedClockwiseImage(from image: NSImage) -> NSImage?
    func flippedImage(from image: NSImage, horizontally: Bool) -> NSImage?
}

@MainActor
final class EditorCanvasResizeService: EditorCanvasResizing {
    func resizedCanvasImage(from image: NSImage, to cropRect: CGRect, fillColor _: NSColor) -> NSImage? {
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
        let pixelRect = CGRect(
            x: floor(targetRect.minX * scaleX),
            y: floor(targetRect.minY * scaleY),
            width: ceil(targetRect.maxX * scaleX) - floor(targetRect.minX * scaleX),
            height: ceil(targetRect.maxY * scaleY) - floor(targetRect.minY * scaleY)
        )
        .intersection(CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))

        guard pixelRect.width >= 1,
              pixelRect.height >= 1,
              let croppedImage = sourceImage.cropping(to: pixelRect)
        else {
            return nil
        }

        // Crop the source pixels directly. This preserves the exact selected pixels
        // and avoids a second render pass that can shift edges through interpolation.
        let logicalSize = NSSize(
            width: CGFloat(croppedImage.width) / scaleX,
            height: CGFloat(croppedImage.height) / scaleY
        )
        return NSImage(cgImage: croppedImage, size: logicalSize)
    }

    func rotatedClockwiseImage(from image: NSImage) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = bitmapContext(
                width: sourceImage.height,
                height: sourceImage.width,
                colorSpace: sourceImage.colorSpace
              )
        else {
            return nil
        }

        let outputPixelSize = CGSize(width: sourceImage.height, height: sourceImage.width)
        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: outputPixelSize))
        context.translateBy(x: outputPixelSize.width, y: 0)
        context.rotate(by: .pi / 2)
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        )

        guard let transformedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: transformedImage, size: CGSize(width: image.editorResizeCanvasSize.height, height: image.editorResizeCanvasSize.width))
    }

    func flippedImage(from image: NSImage, horizontally: Bool) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = bitmapContext(
                width: sourceImage.width,
                height: sourceImage.height,
                colorSpace: sourceImage.colorSpace
              )
        else {
            return nil
        }

        let outputPixelSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: outputPixelSize))

        if horizontally {
            context.translateBy(x: outputPixelSize.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: outputPixelSize.height)
            context.scaleBy(x: 1, y: -1)
        }

        context.draw(sourceImage, in: CGRect(origin: .zero, size: outputPixelSize))

        guard let transformedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: transformedImage, size: image.editorResizeCanvasSize)
    }

    private func bitmapContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace?
    ) -> CGContext? {
        CGContext(
            data: nil,
            width: max(1, width),
            height: max(1, height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
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
