//
//  EditorViewModel.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Combine
import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case oval
    case text
    case highlight
    case blurPixelate

    var id: String {
        rawValue
    }
}

enum EditorToolbarAction: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case oval
    case text
    case highlight
    case blurPixelate
    case undo
    case redo
    case copy
    case save

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .arrow:
            "Arrow"
        case .rectangle:
            "Rectangle"
        case .oval:
            "Oval"
        case .text:
            "Text"
        case .highlight:
            "Highlight"
        case .blurPixelate:
            "Blur/Pixelate"
        case .undo:
            "Undo"
        case .redo:
            "Redo"
        case .copy:
            "Copy"
        case .save:
            "Save"
        }
    }

    var systemImageName: String {
        switch self {
        case .arrow:
            "arrow.up.right"
        case .rectangle:
            "rectangle"
        case .oval:
            "oval"
        case .text:
            "textformat"
        case .highlight:
            "highlighter"
        case .blurPixelate:
            "square.grid.3x3.fill"
        case .undo:
            "arrow.uturn.backward"
        case .redo:
            "arrow.uturn.forward"
        case .copy:
            "doc.on.doc"
        case .save:
            "square.and.arrow.down"
        }
    }

    var shortcutHint: String {
        switch self {
        case .arrow:
            "A"
        case .rectangle:
            "R"
        case .oval:
            "O"
        case .text:
            "T"
        case .highlight:
            "H"
        case .blurPixelate:
            "B"
        case .undo:
            "Z"
        case .redo:
            "Y"
        case .copy:
            "C"
        case .save:
            "S"
        }
    }

    var tool: EditorTool? {
        switch self {
        case .arrow:
            .arrow
        case .rectangle:
            .rectangle
        case .oval:
            .oval
        case .text:
            .text
        case .highlight:
            .highlight
        case .blurPixelate:
            .blurPixelate
        case .undo, .redo, .copy, .save:
            nil
        }
    }

    static let drawingTools: [EditorToolbarAction] = [
        .arrow,
        .rectangle,
        .oval,
        .text,
        .highlight,
        .blurPixelate
    ]

    static let historyCommands: [EditorToolbarAction] = [
        .undo,
        .redo
    ]

    static let outputCommands: [EditorToolbarAction] = [
        .copy,
        .save
    ]
}

@MainActor
final class EditorViewModel: ObservableObject {
    let id = UUID()
    let image: NSImage
    let sourceFileURL: URL?

    @Published private(set) var annotationObjects: [AnnotationObject] = []
    @Published private(set) var activeTool: EditorTool?

    init(image: NSImage, sourceFileURL: URL? = nil) {
        self.image = image
        self.sourceFileURL = sourceFileURL
    }

    func perform(_ action: EditorToolbarAction) {
        if let tool = action.tool {
            activeTool = tool
            logStub("\(action.title) tool selected")
            return
        }

        switch action {
        case .undo:
            undo()
        case .redo:
            redo()
        case .copy:
            copy()
        case .save:
            save()
        case .arrow, .rectangle, .oval, .text, .highlight, .blurPixelate:
            break
        }
    }

    func isSelected(_ action: EditorToolbarAction) -> Bool {
        guard let tool = action.tool else {
            return false
        }

        return activeTool == tool
    }

    private func undo() {
        logStub("Undo requested")
    }

    private func redo() {
        logStub("Redo requested")
    }

    private func copy() {
        logStub("Copy requested")
    }

    private func save() {
        logStub("Save requested")
    }

    private func logStub(_ message: String) {
        print("ClearshotX Editor stub: \(message)")
    }
}
