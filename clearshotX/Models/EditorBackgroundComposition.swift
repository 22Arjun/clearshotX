//
//  EditorBackgroundComposition.swift
//  clearshotX
//
//  Non-destructive presentation state for the editor background tool.
//

import AppKit
import Foundation

struct EditorRGBAColor: Codable, Equatable, Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor {
        nsColor.cgColor
    }
}
enum EditorBackgroundSolidColor: String, Codable, CaseIterable, Identifiable {
    case midnight
    case graphite
    case cloud
    case indigo
    case ocean
    case emerald
    case coral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .graphite: "Graphite"
        case .cloud: "Cloud"
        case .indigo: "Indigo"
        case .ocean: "Ocean"
        case .emerald: "Emerald"
        case .coral: "Coral"
        }
    }

    var color: EditorRGBAColor {
        switch self {
        case .midnight: EditorRGBAColor(red: 0.035, green: 0.047, blue: 0.09)
        case .graphite: EditorRGBAColor(red: 0.16, green: 0.17, blue: 0.2)
        case .cloud: EditorRGBAColor(red: 0.92, green: 0.94, blue: 0.97)
        case .indigo: EditorRGBAColor(red: 0.24, green: 0.2, blue: 0.62)
        case .ocean: EditorRGBAColor(red: 0.03, green: 0.42, blue: 0.66)
        case .emerald: EditorRGBAColor(red: 0.02, green: 0.47, blue: 0.37)
        case .coral: EditorRGBAColor(red: 0.91, green: 0.3, blue: 0.28)
        }
    }
}

enum EditorBackgroundGradient: String, Codable, CaseIterable, Identifiable {
    case aurora
    case dusk
    case lagoon
    case sunrise
    case ultraviolet
    case frost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: "Aurora"
        case .dusk: "Dusk"
        case .lagoon: "Lagoon"
        case .sunrise: "Sunrise"
        case .ultraviolet: "Ultraviolet"
        case .frost: "Frost"
        }
    }

    var colors: [EditorRGBAColor] {
        switch self {
        case .aurora:
            [
                EditorRGBAColor(red: 0.11, green: 0.38, blue: 0.91),
                EditorRGBAColor(red: 0.08, green: 0.8, blue: 0.61),
            ]
        case .dusk:
            [
                EditorRGBAColor(red: 0.13, green: 0.07, blue: 0.36),
                EditorRGBAColor(red: 0.76, green: 0.18, blue: 0.49),
            ]
        case .lagoon:
            [
                EditorRGBAColor(red: 0.02, green: 0.48, blue: 0.68),
                EditorRGBAColor(red: 0.42, green: 0.93, blue: 0.72),
            ]
        case .sunrise:
            [
                EditorRGBAColor(red: 0.98, green: 0.38, blue: 0.28),
                EditorRGBAColor(red: 0.99, green: 0.74, blue: 0.34),
            ]
        case .ultraviolet:
            [
                EditorRGBAColor(red: 0.22, green: 0.08, blue: 0.55),
                EditorRGBAColor(red: 0.23, green: 0.55, blue: 0.97),
                EditorRGBAColor(red: 0.93, green: 0.24, blue: 0.73),
            ]
        case .frost:
            [
                EditorRGBAColor(red: 0.78, green: 0.88, blue: 0.98),
                EditorRGBAColor(red: 0.9, green: 0.79, blue: 0.97),
            ]
        }
    }

    var startPoint: CGPoint {
        switch self {
        case .dusk, .sunrise:
            CGPoint(x: 0, y: 0)
        default:
            CGPoint(x: 0, y: 0.5)
        }
    }

    var endPoint: CGPoint {
        switch self {
        case .dusk, .sunrise:
            CGPoint(x: 1, y: 1)
        default:
            CGPoint(x: 1, y: 0.5)
        }
    }
}

enum EditorBackgroundPaint: Codable, Equatable {
    case none
    case solid(EditorBackgroundSolidColor)
    case gradient(EditorBackgroundGradient)

    var isEnabled: Bool {
        self != .none
    }

    var title: String {
        switch self {
        case .none: "None"
        case let .solid(color): color.title
        case let .gradient(gradient): gradient.title
        }
    }
}

enum EditorBackgroundCanvas: String, Codable, CaseIterable, Identifiable {
    case automatic
    case square
    case landscapeFiveFour
    case portraitFourFive
    case landscapeFourThree
    case landscapeThreeTwo
    case landscapeSixteenNine
    case portraitNineSixteen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Auto"
        case .square: "1 : 1"
        case .landscapeFiveFour: "5 : 4"
        case .portraitFourFive: "4 : 5"
        case .landscapeFourThree: "4 : 3"
        case .landscapeThreeTwo: "3 : 2"
        case .landscapeSixteenNine: "16 : 9"
        case .portraitNineSixteen: "9 : 16"
        }
    }

    var aspectRatio: CGFloat? {
        switch self {
        case .automatic: nil
        case .square: 1
        case .landscapeFiveFour: 5 / 4
        case .portraitFourFive: 4 / 5
        case .landscapeFourThree: 4 / 3
        case .landscapeThreeTwo: 3 / 2
        case .landscapeSixteenNine: 16 / 9
        case .portraitNineSixteen: 9 / 16
        }
    }
}

enum EditorBackgroundAlignment: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case left
    case center
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var id: String { rawValue }

    var horizontalFactor: CGFloat {
        switch self {
        case .topLeft, .left, .bottomLeft: 0
        case .top, .center, .bottom: 0.5
        case .topRight, .right, .bottomRight: 1
        }
    }

    var verticalFactor: CGFloat {
        switch self {
        case .topLeft, .top, .topRight: 0
        case .left, .center, .right: 0.5
        case .bottomLeft, .bottom, .bottomRight: 1
        }
    }

    var accessibilityTitle: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}

struct EditorBackgroundShadow: Codable, Equatable {
    var isEnabled: Bool = true
    var opacity: CGFloat = 0.3
    var radius: CGFloat = 24
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 12

    static let standard = EditorBackgroundShadow()
    static let none = EditorBackgroundShadow(isEnabled: false, opacity: 0, radius: 0, offsetX: 0, offsetY: 0)
}

struct EditorBackgroundComposition: Codable, Equatable {
    static let schemaVersion = 1

    var version = schemaVersion
    var paint: EditorBackgroundPaint = .none
    var canvas: EditorBackgroundCanvas = .automatic
    var padding: CGFloat = 64
    var alignment: EditorBackgroundAlignment = .center
    var cornerRadius: CGFloat = 12
    var shadow: EditorBackgroundShadow = .standard

    static let `default` = EditorBackgroundComposition()

    var isEnabled: Bool {
        paint.isEnabled
    }

    mutating func normalize() {
        version = Self.schemaVersion
        padding = min(max(padding, 0), 400)
        cornerRadius = min(max(cornerRadius, 0), 96)
        shadow.opacity = min(max(shadow.opacity, 0), 1)
        shadow.radius = min(max(shadow.radius, 0), 120)
        shadow.offsetX = min(max(shadow.offsetX, -120), 120)
        shadow.offsetY = min(max(shadow.offsetY, -120), 120)
    }
}
