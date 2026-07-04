//
//  EditorWindowManager.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import SwiftUI

@MainActor
final class EditorWindowManager {
    private let minContentSize = NSSize(width: 680, height: 460)
    private let maxContentSize = NSSize(width: 1180, height: 820)
    private let toolbarHeight: CGFloat = 54
    private let contentPadding: CGFloat = 48

    private var windows: [UUID: EditorWindowRecord] = [:]

    func showEditor(for capture: CaptureResult) {
        showEditor(image: capture.image, sourceFileURL: capture.fileURL)
    }

    func showEditor(image: NSImage, sourceFileURL: URL? = nil) {
        let viewModel = EditorViewModel(image: image, sourceFileURL: sourceFileURL)
        let editorView = EditorView(viewModel: viewModel)
        let windowID = viewModel.id
        let closeDelegate = EditorWindowCloseDelegate { [weak self] in
            self?.windows[windowID] = nil
        }
        let contentSize = preferredContentSize(for: image)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = editorTitle(for: sourceFileURL)
        window.contentMinSize = minContentSize
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.tabbingMode = .disallowed
        window.delegate = closeDelegate
        window.contentView = NSHostingView(rootView: editorView)
        window.center()

        windows[windowID] = EditorWindowRecord(window: window, closeDelegate: closeDelegate)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func preferredContentSize(for image: NSImage) -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenLimitedSize = NSSize(
            width: min(maxContentSize.width, visibleFrame.width * 0.86),
            height: min(maxContentSize.height, visibleFrame.height * 0.86)
        )
        let availableCanvasSize = NSSize(
            width: max(1, screenLimitedSize.width - contentPadding),
            height: max(1, screenLimitedSize.height - toolbarHeight - contentPadding)
        )
        let fittedImageSize = image.editorDisplaySize.aspectFitted(in: availableCanvasSize)

        return NSSize(
            width: min(
                screenLimitedSize.width,
                max(minContentSize.width, fittedImageSize.width + contentPadding)
            ),
            height: min(
                screenLimitedSize.height,
                max(minContentSize.height, fittedImageSize.height + toolbarHeight + contentPadding)
            )
        )
    }

    private func editorTitle(for sourceFileURL: URL?) -> String {
        guard let sourceFileURL else {
            return "ClearshotX Editor"
        }

        return "Edit \(sourceFileURL.lastPathComponent)"
    }
}

private struct EditorWindowRecord {
    let window: NSWindow
    let closeDelegate: EditorWindowCloseDelegate
}

private final class EditorWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private extension NSImage {
    var editorDisplaySize: NSSize {
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

        let scale = min(boundingSize.width / width, boundingSize.height / height, 1)
        return NSSize(width: width * scale, height: height * scale)
    }
}
