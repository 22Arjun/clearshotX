//
//  CaptureFileDragSource.swift
//  clearshotX
//
//  Created by Codex on 13/07/26.
//

import AppKit
import SwiftUI

struct CaptureFileDragSource: NSViewRepresentable {
    let fileURL: URL
    let dragFileURL: URL
    let image: NSImage
    let onDragBegan: () -> Void
    let onDragEnded: (_ didDrop: Bool) -> Void

    func makeNSView(context: Context) -> CaptureFileDragSourceView {
        let view = CaptureFileDragSourceView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: CaptureFileDragSourceView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: CaptureFileDragSourceView) {
        view.configure(
            fileURL: fileURL,
            dragFileURL: dragFileURL,
            sourceImage: image
        )
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

final class CaptureFileDragSourceView: NSView, NSDraggingSource {
    var fileURL: URL?
    var sourceImage: NSImage?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((_ didDrop: Bool) -> Void)?

    private let dragThreshold: CGFloat = 4
    private var mouseDownLocation: CGPoint?
    private var hasStartedDrag = false
    private var activePasteboardWriter: CaptureDragPasteboardWriter?
    private var localMouseMonitor: Any?
    private var preparedPayload: CaptureDragPayload?
    private var preparedPreview: NSImage?

    deinit {
        removeLocalMouseMonitor()
        releasePreparedPayload()
    }

    override var isFlipped: Bool {
        true
    }

    // The quick-access panel is transparent. Explicitly keep thumbnail drags
    // from being interpreted as background window drags by AppKit.
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeLocalMouseMonitor()
        } else {
            installLocalMouseMonitorIfNeeded()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func configure(fileURL: URL, dragFileURL: URL, sourceImage: NSImage) {
        self.sourceImage = sourceImage

        guard self.fileURL != fileURL || preparedPayload?.fileURL != dragFileURL else {
            return
        }

        releasePreparedPayload()
        self.fileURL = fileURL
        preparedPreview = dragPreview(
            for: sourceImage,
            size: dragPreviewSize(for: sourceImage.size)
        )
        preparedPayload = CaptureDragPayload(
            directoryURL: dragFileURL.deletingLastPathComponent(),
            fileURL: dragFileURL
        )
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        _ = beginDragIfNeeded(with: event)
    }

    private func beginDragIfNeeded(with event: NSEvent) -> Bool {
        guard !hasStartedDrag,
              let sourceImage,
              let mouseDownLocation,
              let preparedPayload,
              let preparedPreview
        else {
            return false
        }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(
            currentLocation.x - mouseDownLocation.x,
            currentLocation.y - mouseDownLocation.y
        )
        guard distance >= dragThreshold else {
            return false
        }

        let pasteboardWriter = CaptureDragPasteboardWriter(
            fileURL: preparedPayload.fileURL
        )
        activePasteboardWriter = pasteboardWriter
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
        let previewSize = dragPreviewSize(for: sourceImage.size)
        draggingItem.setDraggingFrame(
            NSRect(
                x: currentLocation.x - previewSize.width / 2,
                y: currentLocation.y - previewSize.height / 2,
                width: previewSize.width,
                height: previewSize.height
            ),
            contents: preparedPreview
        )

        hasStartedDrag = true

        let session = beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    private func installLocalMouseMonitorIfNeeded() {
        guard localMouseMonitor == nil else {
            return
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMonitoredMouseEvent(event) ?? event
        }
    }

    private func removeLocalMouseMonitor() {
        guard let localMouseMonitor else {
            return
        }

        NSEvent.removeMonitor(localMouseMonitor)
        self.localMouseMonitor = nil
    }

    private func handleMonitoredMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else {
            return event
        }

        switch event.type {
        case .leftMouseDown:
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else {
                return event
            }

            mouseDownLocation = location
            hasStartedDrag = false
            return event

        case .leftMouseDragged:
            guard mouseDownLocation != nil else {
                return event
            }

            // The controls sit above this view and normally own their mouse
            // sequence. Consume only the event that crosses the threshold;
            // AppKit's dragging session owns the remaining drag events.
            return beginDragIfNeeded(with: event) ? nil : event

        case .leftMouseUp:
            if !hasStartedDrag {
                resetDragState()
            }
            return event

        default:
            return event
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint
    ) {
        onDragBegan?()
    }

    override func mouseUp(with event: NSEvent) {
        if !hasStartedDrag {
            resetDragState()
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .generic]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let didDrop = !operation.isEmpty
        resetDragState()
        if didDrop, let preparedPayload {
            CaptureDragPayloadFactory.remove(preparedPayload, after: 60 * 60)
        }
        onDragEnded?(didDrop)
    }

    private func dragPreviewSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: 120, height: 80)
        }

        let scale = min(180 / imageSize.width, 120 / imageSize.height, 1)
        return NSSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
    }

    private func dragPreview(for image: NSImage, size: NSSize) -> NSImage {
        let preview = NSImage(size: size)
        preview.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        image.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        preview.unlockFocus()
        return preview
    }

    private func releasePreparedPayload() {
        guard let preparedPayload else {
            preparedPreview = nil
            return
        }

        CaptureDragPayloadFactory.remove(
            preparedPayload,
            after: 60 * 60
        )
        self.preparedPayload = nil
        preparedPreview = nil
    }

    private func resetDragState() {
        mouseDownLocation = nil
        hasStartedDrag = false
        activePasteboardWriter = nil
    }
}

private struct CaptureDragPayload: Sendable {
    let directoryURL: URL
    let fileURL: URL
}

private enum CaptureDragPayloadFactory {
    nonisolated static func remove(_ payload: CaptureDragPayload, after delay: TimeInterval) {
        let remove: @Sendable () -> Void = {
            _ = try? FileManager.default.removeItem(at: payload.directoryURL)
        }

        guard delay > 0 else {
            remove()
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: remove
        )
    }

}

private final class CaptureDragPasteboardWriter: NSObject, NSPasteboardWriting {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .png, .tiff]
    }

    func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        type == .fileURL ? [] : .promised
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            fileURL.absoluteString
        case .png:
            try? Data(contentsOf: fileURL, options: .mappedIfSafe)
        case .tiff:
            NSImage(contentsOf: fileURL)?.tiffRepresentation
        default:
            nil
        }
    }
}
