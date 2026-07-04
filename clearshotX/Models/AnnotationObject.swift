//
//  AnnotationObject.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Foundation

enum AnnotationObjectKind: String, CaseIterable, Identifiable {
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

struct AnnotationStyle: Equatable {
    var strokeColor: NSColor = .controlAccentColor
    var fillColor: NSColor = .clear
    var lineWidth: CGFloat = 3
    var opacity: CGFloat = 1
}

struct AnnotationObject: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationObjectKind
    var frame: CGRect
    var style: AnnotationStyle

    init(
        id: UUID = UUID(),
        kind: AnnotationObjectKind,
        frame: CGRect = .zero,
        style: AnnotationStyle = AnnotationStyle()
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.style = style
    }
}
