//
//  ScrollingCaptureCoordinatorModels.swift
//  clearshotX
//

import Foundation

enum ScrollingCaptureMode: Equatable {
    case manual
    case automatic
}

enum ScrollingCaptureHUDPhase: Equatable {
    case starting
    case ready
    case capturing
    case guidance
    case paused
    case finishing
}

struct ScrollingCaptureHUDState: Equatable {
    var phase: ScrollingCaptureHUDPhase
    var acceptedFrameCount: Int
    var rejectedFrameCount: Int
    var outputPixelWidth: Int
    var outputPixelHeight: Int
    var mode: ScrollingCaptureMode?
    /// Only meaningful in automatic mode: whether the person explicitly pressed
    /// Pause, as opposed to auto-scroll being paused only because the cursor is
    /// currently outside the selected area. Manual mode's `phase` alone already
    /// reflects user intent directly, since manual pausing has no other cause.
    var isUserPaused = false
    /// True only while automatic mode is paused solely because the cursor is
    /// outside the selected area (and the user has not also pressed Pause).
    var isAwaitingHover = false

    static let starting = ScrollingCaptureHUDState(
        phase: .starting,
        acceptedFrameCount: 0,
        rejectedFrameCount: 0,
        outputPixelWidth: 0,
        outputPixelHeight: 0,
        mode: nil
    )

    var title: String {
        switch phase {
        case .starting:
            "Preparing scrolling capture…"
        case .ready:
            "Ready to capture"
        case .capturing:
            switch mode {
            case .manual:
                acceptedFrameCount <= 1 ? "Scrolling capture" : "Capturing scroll"
            case .automatic:
                acceptedFrameCount <= 1 ? "Auto-scrolling page" : "Capturing page"
            case nil:
                "Capturing page"
            }
        case .guidance:
            "Scroll a little slower"
        case .paused:
            isAwaitingHover ? "Auto-scroll paused" : "Capture paused"
        case .finishing:
            "Finishing capture…"
        }
    }

    var detail: String {
        switch phase {
        case .starting:
            "Connecting to the selected area"
        case .ready:
            "Press Start Capture, then scroll naturally. You can switch to Auto Scroll before you start scrolling."
        case .capturing:
            switch mode {
            case .manual:
                "Scroll naturally inside the selected area. ClearshotX will capture settled movement."
            case .automatic:
                "ClearshotX is scrolling and capturing each settled page step."
            case nil:
                "Capturing each settled page step."
            }
        case .guidance:
            "Retrying this area with a smaller automatic scroll step."
        case .paused:
            switch mode {
            case .manual:
                "Resume when you are ready to keep capturing manual scroll movement."
            case .automatic:
                isAwaitingHover
                    ? "Move your cursor back over the selected area to continue auto-scrolling."
                    : "Resume to continue automatic scrolling from this position."
            case nil:
                "Resume to continue capturing."
            }
        case .finishing:
            "Assembling and saving the accepted pixels"
        }
    }

    var dimensionsText: String? {
        guard outputPixelWidth > 0, outputPixelHeight > 0 else { return nil }
        return "\(outputPixelWidth) × \(outputPixelHeight) px"
    }

    var canFinish: Bool {
        acceptedFrameCount > 0 && phase != .finishing
    }

    var canStartCapture: Bool {
        phase == .ready
    }

    /// Switching mid-capture only makes sense before any real scroll movement
    /// has been accepted: once the document has actually grown, there is no
    /// existing manual progress to hand off, and starting automatic capture
    /// over would silently discard it.
    var canSwitchToAutoScroll: Bool {
        mode == .manual && acceptedFrameCount <= 1 && (phase == .capturing || phase == .guidance)
    }

    var canPause: Bool {
        phase == .capturing || phase == .guidance || phase == .paused
    }

    var pauseButtonTitle: String {
        let isEffectivelyPaused = mode == .automatic ? isUserPaused : phase == .paused
        return isEffectivelyPaused ? "Resume" : "Pause"
    }

    var acceptedFramesText: String {
        "\(acceptedFrameCount) \(acceptedFrameCount == 1 ? "frame" : "frames")"
    }
}

enum ScrollingCaptureHUDReducer {
    static let guidanceRejectionThreshold = 5

    static func applying(
        _ decision: ScrollingCaptureFrameDecision,
        to state: ScrollingCaptureHUDState,
        consecutiveRejections: inout Int
    ) -> ScrollingCaptureHUDState {
        switch decision {
        case let .started(progress), let .appended(progress):
            consecutiveRejections = 0
            return state.updating(progress: progress, phase: .capturing)

        case let .rebased(progress):
            consecutiveRejections = 0
            return state.updating(progress: progress, phase: .capturing)

        case let .duplicate(progress):
            return state.updating(progress: progress, phase: state.phase)

        case let .rejected(_, progress):
            consecutiveRejections += 1
            let phase: ScrollingCaptureHUDPhase = consecutiveRejections
                >= guidanceRejectionThreshold ? .guidance : .capturing
            return state.updating(progress: progress, phase: phase)

        case let .reachedOutputLimit(progress):
            consecutiveRejections = 0
            return state.updating(progress: progress, phase: .finishing)
        }
    }
}

private extension ScrollingCaptureHUDState {
    func updating(
        progress: ScrollingCaptureProgress,
        phase: ScrollingCaptureHUDPhase
    ) -> ScrollingCaptureHUDState {
        // A frame decision only ever arrives while actively capturing, never
        // while paused, so any pause-related state from a prior pause is stale.
        ScrollingCaptureHUDState(
            phase: phase,
            acceptedFrameCount: progress.acceptedFrameCount,
            rejectedFrameCount: progress.rejectedFrameCount,
            outputPixelWidth: progress.outputPixelWidth,
            outputPixelHeight: progress.outputPixelHeight,
            mode: mode,
            isUserPaused: false,
            isAwaitingHover: false
        )
    }
}
