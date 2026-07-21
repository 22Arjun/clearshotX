//
//  EditorCompositionLayoutEngine.swift
//  clearshotX
//
//  Pure geometry for the background composition. Preview and export both consume
//  the same render plan so changing UI scale cannot change output geometry.
//

import CoreGraphics
import Foundation

struct EditorCompositionRenderPlan: Equatable {
    let canvasSize: CGSize
    let contentFrame: CGRect
    let paint: EditorBackgroundPaint
    let cornerRadius: CGFloat
    let shadow: EditorBackgroundShadow

    var canvasBounds: CGRect {
        CGRect(origin: .zero, size: canvasSize)
    }

    var isCompositionEnabled: Bool {
        paint.isEnabled
    }

    static func identity(contentSize: CGSize) -> EditorCompositionRenderPlan {
        let size = contentSize.editorCompositionSanitized
        return EditorCompositionRenderPlan(
            canvasSize: size,
            contentFrame: CGRect(origin: .zero, size: size),
            paint: .none,
            cornerRadius: 0,
            shadow: .none
        )
    }
}
struct EditorCompositionLayoutEngine {
    func makePlan(
        contentSize: CGSize,
        composition: EditorBackgroundComposition
    ) -> EditorCompositionRenderPlan {
        let contentSize = contentSize.editorCompositionSanitized

        guard composition.isEnabled else {
            return .identity(contentSize: contentSize)
        }

        let padding = min(max(composition.padding, 0), 400)
        let minimumCanvasSize = CGSize(
            width: contentSize.width + padding * 2,
            height: contentSize.height + padding * 2
        )
        let canvasSize = canvasSize(
            containing: minimumCanvasSize,
            aspectRatio: composition.canvas.aspectRatio
        )
        let safeBounds = CGRect(origin: .zero, size: canvasSize)
            .insetBy(dx: padding, dy: padding)
        let freeWidth = max(0, safeBounds.width - contentSize.width)
        let freeHeight = max(0, safeBounds.height - contentSize.height)
        let contentOrigin = CGPoint(
            x: safeBounds.minX + freeWidth * composition.alignment.horizontalFactor,
            y: safeBounds.minY + freeHeight * composition.alignment.verticalFactor
        )
        let cornerRadius = min(
            max(composition.cornerRadius, 0),
            min(contentSize.width, contentSize.height) / 2
        )

        return EditorCompositionRenderPlan(
            canvasSize: canvasSize,
            contentFrame: CGRect(origin: contentOrigin, size: contentSize),
            paint: composition.paint,
            cornerRadius: cornerRadius,
            shadow: composition.shadow
        )
    }

    private func canvasSize(
        containing minimumSize: CGSize,
        aspectRatio: CGFloat?
    ) -> CGSize {
        guard let aspectRatio,
              aspectRatio.isFinite,
              aspectRatio > 0
        else {
            return minimumSize
        }

        if minimumSize.width / minimumSize.height < aspectRatio {
            return CGSize(
                width: minimumSize.height * aspectRatio,
                height: minimumSize.height
            )
        }

        return CGSize(
            width: minimumSize.width,
            height: minimumSize.width / aspectRatio
        )
    }
}

private extension CGSize {
    var editorCompositionSanitized: CGSize {
        CGSize(
            width: width.isFinite && width > 0 ? width : 1,
            height: height.isFinite && height > 0 ? height : 1
        )
    }
}
