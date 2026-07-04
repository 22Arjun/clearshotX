//
//  EditorView.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import QuartzCore
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbarView(viewModel: viewModel)
            Divider()
            EditorCanvasView(
                image: viewModel.image,
                annotationObjects: viewModel.annotationObjects
            )
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EditorToolbarView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 10) {
            toolbarGroup(EditorToolbarAction.drawingTools)
            toolbarDivider
            toolbarGroup(EditorToolbarAction.historyCommands)
            toolbarDivider
            toolbarGroup(EditorToolbarAction.outputCommands)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.regularMaterial)
    }

    private func toolbarGroup(_ actions: [EditorToolbarAction]) -> some View {
        HStack(spacing: 5) {
            ForEach(actions) { action in
                Button {
                    viewModel.perform(action)
                } label: {
                    Image(systemName: action.systemImageName)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(EditorToolbarButtonStyle(isSelected: viewModel.isSelected(action)))
                .help("\(action.title) (\(action.shortcutHint))")
            }
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 2)
    }
}

private struct EditorToolbarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        }

        if isPressed {
            return Color(nsColor: .selectedControlColor).opacity(0.32)
        }

        return Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }
}

private struct EditorCanvasView: NSViewRepresentable {
    let image: NSImage
    let annotationObjects: [AnnotationObject]

    func makeNSView(context: Context) -> EditorCanvasNSView {
        let view = EditorCanvasNSView()
        view.configure(image: image, annotationObjects: annotationObjects)
        return view
    }

    func updateNSView(_ nsView: EditorCanvasNSView, context: Context) {
        nsView.configure(image: image, annotationObjects: annotationObjects)
    }
}

private final class EditorCanvasNSView: NSView {
    private let imageContainerLayer = CALayer()
    private let imageLayer = CALayer()
    private let annotationContainerLayer = CALayer()

    private var currentImage: NSImage?
    private var annotationObjects: [AnnotationObject] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerScale()
    }

    override func layout() {
        super.layout()
        layoutCanvasLayers()
    }

    func configure(image: NSImage, annotationObjects: [AnnotationObject]) {
        currentImage = image
        self.annotationObjects = annotationObjects
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        rebuildAnnotationLayers()
        needsLayout = true
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        layer?.masksToBounds = true

        imageContainerLayer.shadowColor = NSColor.black.cgColor
        imageContainerLayer.shadowOpacity = 0.22
        imageContainerLayer.shadowRadius = 20
        imageContainerLayer.shadowOffset = CGSize(width: 0, height: 10)

        imageLayer.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        imageLayer.cornerRadius = 10
        imageLayer.masksToBounds = true

        // Core Animation layers are the canvas foundation here because future tools can map
        // each annotation object to its own CALayer/CAShapeLayer for ordering, hit testing,
        // transforms, and export without making SwiftUI redraw the captured bitmap itself.
        annotationContainerLayer.name = "AnnotationContainerLayer"
        annotationContainerLayer.cornerRadius = 10
        annotationContainerLayer.masksToBounds = true

        layer?.addSublayer(imageContainerLayer)
        imageContainerLayer.addSublayer(imageLayer)
        imageContainerLayer.addSublayer(annotationContainerLayer)
        updateLayerScale()
    }

    private func layoutCanvasLayers() {
        guard let currentImage else {
            imageContainerLayer.frame = .zero
            return
        }

        let availableBounds = bounds.insetBy(dx: 28, dy: 28)
        let imageSize = currentImage.editorCanvasSize
        let fittedSize = imageSize.aspectFitted(in: availableBounds.size)
        let imageFrame = CGRect(
            x: availableBounds.midX - fittedSize.width / 2,
            y: availableBounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageContainerLayer.frame = imageFrame
        imageLayer.frame = imageContainerLayer.bounds
        annotationContainerLayer.frame = imageContainerLayer.bounds
        imageContainerLayer.shadowPath = CGPath(
            roundedRect: imageContainerLayer.bounds,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        CATransaction.commit()
    }

    private func rebuildAnnotationLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        annotationContainerLayer.sublayers = []
        CATransaction.commit()
    }

    private func updateLayerScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        imageContainerLayer.contentsScale = scale
        imageLayer.contentsScale = scale
        annotationContainerLayer.contentsScale = scale
    }
}

private extension NSImage {
    var editorCanvasSize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSSize(width: 960, height: 540)
        }

        return NSSize(width: cgImage.width, height: cgImage.height)
    }
}

private extension NSSize {
    func aspectFitted(in boundingSize: NSSize) -> NSSize {
        guard width > 0, height > 0, boundingSize.width > 0, boundingSize.height > 0 else {
            return .zero
        }

        let scale = min(boundingSize.width / width, boundingSize.height / height)
        return NSSize(width: width * scale, height: height * scale)
    }
}
