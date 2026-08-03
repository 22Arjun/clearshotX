//
//  ScrollingCaptureAutoCaptureController.swift
//  clearshotX
//

import CoreGraphics
import Foundation

nonisolated struct ScrollingCaptureAutoCaptureConfiguration: Equatable, Sendable {
    /// Scroll in AppKit points; the captured offset is measured independently in
    /// native pixels, so Retina output never depends on this estimate.
    /// A deliberately short, readable move. It leaves generous registration
    /// overlap while allowing the person to follow the page and press Done at a
    /// meaningful boundary instead of watching viewport-sized jumps.
    var viewportStepFraction = 0.32
    var minimumStepPoints = 12
    /// Each logical step is delivered as small continuous-wheel pulses. This is
    /// what makes the selected app visibly scroll rather than snap between two
    /// far-apart positions.
    var maximumPulsePoints = 36
    var pulseInterval: Duration = .milliseconds(16)
    /// Keeps each accepted page position visible long enough to inspect before
    /// the next automatic move begins.
    var readableStepPause: Duration = .milliseconds(170)
    /// Number of fresh frames evaluated at the same post-scroll position before
    /// declaring a viewport unregistrable. Retrying the image is safe; moving
    /// the document backwards and forwards is not.
    var maximumRetries = 5
    var alignmentRecoveryDelay: Duration = .milliseconds(70)
    var initialSettleDelay: Duration = .milliseconds(90)
    var settleProbeDelay: Duration = .milliseconds(24)
    var maximumSettleProbes = 5
    var stationaryStepsToFinish = 2
    var maximumSteps: Int?

    func canRunStep(_ completedStepCount: Int) -> Bool {
        guard let maximumSteps else { return true }
        return completedStepCount < maximumSteps
    }
}

nonisolated enum ScrollingCaptureAutoCaptureError: LocalizedError, Equatable {
    case alreadyRunning
    case notPrepared
    case eventCreationFailed
    case postEventPermissionDenied
    case unreliableAlignment
    case invalidScrollRegion
    case frameAcquisitionTimedOut

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "An automatic scrolling capture is already running."
        case .notPrepared:
            "The automatic scrolling capture source was not prepared."
        case .eventCreationFailed:
            "ClearshotX could not create the automatic scroll event."
        case .postEventPermissionDenied:
            "Automatic scrolling needs permission to control this Mac."
        case .unreliableAlignment:
            "The page could not be aligned reliably, so capture stopped before making a broken seam."
        case .invalidScrollRegion:
            "The selected region is too small for automatic scrolling capture."
        case .frameAcquisitionTimedOut:
            "ClearshotX did not receive a new frame from the selected area in time."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreliableAlignment:
            "Keep the page unobstructed and try a slightly taller region."
        case .postEventPermissionDenied:
            "Allow ClearshotX in System Settings › Privacy & Security › Accessibility, then try again."
        case .frameAcquisitionTimedOut:
            "Keep the selected area visible on screen, then try again."
        default:
            "Select the scrolling region again and retry."
        }
    }
}

nonisolated protocol ScrollingCaptureAutoCapturing: AnyObject, Sendable {
    typealias ProgressHandler = @Sendable (ScrollingCaptureFrameDecision) -> Void
    typealias PreviewHandler = @Sendable (CGImage) -> Void
    typealias CompletionHandler = @Sendable (Result<CGImage?, Error>) -> Void

    func start(
        selectedRegion: CGRect,
        onProgress: @escaping ProgressHandler,
        onPreview: @escaping PreviewHandler,
        onCompletion: @escaping CompletionHandler
    ) async throws -> ScrollingCaptureRegionGeometry

    func setPaused(_ isPaused: Bool)
    func finish()
    func cancel()
}

/// Owns the deterministic capture loop: scroll, settle, capture, register, append.
/// No user scroll cadence enters the algorithm. An ambiguous viewport is sampled
/// again in place; the controller never scrolls backwards to retry alignment.
nonisolated final class ScrollingCaptureAutoCaptureController:
    ScrollingCaptureAutoCapturing,
    @unchecked Sendable
{
    private struct ControlState {
        var isRunning = false
        var isPaused = false
        var shouldFinish = false
        var isCancelled = false
    }

    private struct StepResult {
        let frame: CGImage
        let match: ScrollingCaptureStitchMatch
    }

    private let frameSource: ScrollingCaptureDiscreteFrameSourcing
    private let scrollDriver: ScrollingCaptureScrollDriving
    private let stitchEngine: ScrollingCaptureStitchEngine
    private let captureConfiguration: ScrollingCaptureConfiguration
    private let autoConfiguration: ScrollingCaptureAutoCaptureConfiguration
    private let lock = NSLock()
    private var control = ControlState()
    private var captureTask: Task<Void, Never>?

    init(
        frameSource: ScrollingCaptureDiscreteFrameSourcing =
            ScrollingCaptureContinuousDiscreteFrameSource(),
        scrollDriver: ScrollingCaptureScrollDriving = ScrollingCaptureCGEventScrollDriver(),
        stitchEngine: ScrollingCaptureStitchEngine = ScrollingCaptureStitchEngine(),
        captureConfiguration: ScrollingCaptureConfiguration = .init(),
        autoConfiguration: ScrollingCaptureAutoCaptureConfiguration = .init()
    ) {
        self.frameSource = frameSource
        self.scrollDriver = scrollDriver
        self.stitchEngine = stitchEngine
        self.captureConfiguration = captureConfiguration
        self.autoConfiguration = autoConfiguration
    }

    func start(
        selectedRegion: CGRect,
        onProgress: @escaping ProgressHandler,
        onPreview: @escaping PreviewHandler,
        onCompletion: @escaping CompletionHandler
    ) async throws -> ScrollingCaptureRegionGeometry {
        guard selectedRegion.width >= 2, selectedRegion.height >= 2 else {
            throw ScrollingCaptureAutoCaptureError.invalidScrollRegion
        }
        try reserveStart()
        do {
            let geometry = try await frameSource.prepare(selectedRegion: selectedRegion)
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let result: Result<CGImage?, Error>
                do {
                    result = .success(
                        try await self.run(
                            geometry: geometry,
                            onProgress: onProgress,
                            onPreview: onPreview
                        )
                    )
                } catch is CancellationError {
                    result = .success(nil)
                } catch {
                    result = .failure(error)
                }
                await self.frameSource.stop()
                self.clearState()
                onCompletion(result)
            }
            install(task: task)
            return geometry
        } catch {
            clearState()
            await frameSource.stop()
            throw error
        }
    }

    func setPaused(_ isPaused: Bool) {
        lock.lock()
        if control.isRunning, !control.isCancelled {
            control.isPaused = isPaused
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        if control.isRunning, !control.isCancelled {
            control.shouldFinish = true
            control.isPaused = false
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        control.isCancelled = true
        control.isPaused = false
        let task = captureTask
        lock.unlock()
        task?.cancel()
    }

    private func run(
        geometry: ScrollingCaptureRegionGeometry,
        onProgress: @escaping ProgressHandler,
        onPreview: @escaping PreviewHandler
    ) async throws -> CGImage? {
        var previous = try await frameSource.captureFrame()
        let compositor = try ScrollingCaptureCompositor(
            firstFrame: previous,
            contentInsets: captureConfiguration.contentInsets
        )
        let previewPipeline = ScrollingCapturePreviewPipeline(
            contentInsets: captureConfiguration.contentInsets,
            publication: onPreview
        )
        defer { previewPipeline.stop() }

        var acceptedFrames = 1
        var rejectedFrames = 0
        var lastAlignment: ScrollingCaptureAlignment?
        var progress = makeProgress(
            compositor: compositor,
            acceptedFrames: acceptedFrames,
            rejectedFrames: rejectedFrames,
            lastAlignment: lastAlignment
        )
        let started = ScrollingCaptureFrameDecision.started(progress)
        onProgress(started)
        previewPipeline.submit(frame: previous, decision: started)

        let selectionCenter = CGPoint(
            x: geometry.globalRect.midX,
            y: geometry.globalRect.midY
        )
        let baseDelta = max(
            autoConfiguration.minimumStepPoints,
            Int((geometry.globalRect.height * autoConfiguration.viewportStepFraction).rounded())
        )
        var stationaryCount = 0
        var steps = 0

        captureLoop: while autoConfiguration.canRunStep(steps) {
            try Task.checkCancellation()
            try await waitWhilePaused()
            let state = currentControl()
            if state.isCancelled { return nil }
            if state.shouldFinish { break }

            guard let step = try await captureReliableStep(
                previous: previous,
                initialDelta: baseDelta,
                location: selectionCenter
            ) else {
                // Done was pressed during a visible micro-scroll. The preceding
                // stitched frame is already complete, so finish immediately
                // rather than risk appending a partially moved viewport.
                break captureLoop
            }
            steps += 1

            switch step.match.disposition {
            case .stationary:
                stationaryCount += 1
                previous = step.frame
                try compositor.refreshDeferredPixels(from: step.frame)
                progress = makeProgress(
                    compositor: compositor,
                    acceptedFrames: acceptedFrames,
                    rejectedFrames: rejectedFrames,
                    lastAlignment: lastAlignment
                )
                onProgress(.duplicate(progress))
                if stationaryCount >= autoConfiguration.stationaryStepsToFinish {
                    break captureLoop
                }

            case .accept:
                stationaryCount = 0
                if acceptedFrames == 1 {
                    try compositor.updateContentInsets(
                        step.match.detectedContentInsets,
                        latestFrame: step.frame
                    )
                }
                let proposedHeight = compositor.outputHeight + step.match.verticalOffset
                guard captureConfiguration.permitsOutput(
                    width: compositor.outputWidth,
                    height: proposedHeight
                ) else {
                    progress = makeProgress(
                        compositor: compositor,
                        acceptedFrames: acceptedFrames,
                        rejectedFrames: rejectedFrames,
                        lastAlignment: lastAlignment
                    )
                    onProgress(.reachedOutputLimit(progress))
                    return try compositor.makeImage()
                }

                try compositor.append(
                    frame: step.frame,
                    verticalOffset: step.match.verticalOffset
                )
                // The settle probe is a second same-position observation, so the
                // newest native strip is safe to commit without waiting another step.
                try compositor.refreshDeferredPixels(from: step.frame)
                previous = step.frame
                acceptedFrames += 1
                lastAlignment = ScrollingCaptureAlignment(
                    verticalOffset: step.match.verticalOffset,
                    difference: Double(max(0, 1 - step.match.correlation)),
                    confidence: Double(step.match.correlation)
                )
                progress = makeProgress(
                    compositor: compositor,
                    acceptedFrames: acceptedFrames,
                    rejectedFrames: rejectedFrames,
                    lastAlignment: lastAlignment
                )
                let decision = ScrollingCaptureFrameDecision.appended(progress)
                onProgress(decision)
                previewPipeline.submit(frame: step.frame, decision: decision)
                try await Task.sleep(for: autoConfiguration.readableStepPause)

            case .retryWithSmallerScrollDelta:
                // The current position was sampled repeatedly without a credible
                // overlap. Keep the fully verified prefix instead of moving the
                // page backwards or showing an error after a long capture.
                rejectedFrames += 1
                progress = makeProgress(
                    compositor: compositor,
                    acceptedFrames: acceptedFrames,
                    rejectedFrames: rejectedFrames,
                    lastAlignment: lastAlignment
                )
                onProgress(.rejected(.insufficientOverlap, progress))
                return try compositor.makeImage()
            }
        }

        return try compositor.makeImage()
    }

    private func captureReliableStep(
        previous: CGImage,
        initialDelta: Int,
        location: CGPoint
    ) async throws -> StepResult? {
        var best: StepResult?

        // Advance exactly once. A low-confidence alignment is normally a frame
        // that was captured during redraw/hover animation rather than proof the
        // page needs to move in the opposite direction. Re-sample the unchanged
        // viewport instead of visibly bouncing it up and down.
        guard try await driveSmoothScroll(
            verticalDelta: initialDelta,
            at: location
        ) else {
            return nil
        }

        for attempt in 0..<max(1, autoConfiguration.maximumRetries) {
            try Task.checkCancellation()
            let candidate = try await captureSettledFrame()
            if currentControl().shouldFinish { return nil }
            let match = try stitchEngine.match(previous: previous, current: candidate)
            let result = StepResult(frame: candidate, match: match)

            if match.disposition != .retryWithSmallerScrollDelta {
                return result
            }
            if best == nil || match.correlation > best!.match.correlation {
                best = result
            }
            if attempt + 1 < autoConfiguration.maximumRetries {
                try await Task.sleep(for: autoConfiguration.alignmentRecoveryDelay)
            }
        }
        if let best { return best }
        return StepResult(
            frame: previous,
            match: try stitchEngine.match(previous: previous, current: previous)
        )
    }

    /// Delivers a logical scroll in several continuous pixel-wheel events.
    /// Splitting the exact requested delta avoids a visible jump while keeping
    /// capture/stitching deterministic: there is still one native frame taken
    /// only after the entire logical step has settled.
    private func driveSmoothScroll(
        verticalDelta: Int,
        at location: CGPoint
    ) async throws -> Bool {
        guard verticalDelta != 0 else { return true }

        let magnitude = abs(verticalDelta)
        let pulseLimit = max(1, autoConfiguration.maximumPulsePoints)
        let pulseCount = 1 + (magnitude - 1) / pulseLimit
        let basePulse = magnitude / pulseCount
        let remainder = magnitude % pulseCount
        let direction = verticalDelta < 0 ? -1 : 1

        for index in 0..<pulseCount {
            try Task.checkCancellation()
            try await waitWhilePaused()
            let control = currentControl()
            if control.isCancelled { throw CancellationError() }
            if control.shouldFinish { return false }

            let pulse = basePulse + (index < remainder ? 1 : 0)
            try scrollDriver.scroll(
                verticalDelta: direction * pulse,
                at: location
            )
            if index + 1 < pulseCount {
                try await Task.sleep(for: autoConfiguration.pulseInterval)
            }
        }
        return true
    }

    private func captureSettledFrame() async throws -> CGImage {
        try await Task.sleep(for: autoConfiguration.initialSettleDelay)
        var latest = try await frameSource.captureFrame()
        guard autoConfiguration.maximumSettleProbes > 0 else { return latest }

        for _ in 0..<autoConfiguration.maximumSettleProbes {
            try Task.checkCancellation()
            try await Task.sleep(for: autoConfiguration.settleProbeDelay)
            let probe = try await frameSource.captureFrame()
            if let match = try? stitchEngine.match(previous: latest, current: probe),
               match.isStationary {
                return probe
            }
            latest = probe
        }
        // Dynamic ads/video may never become pixel-identical. The newest frame is
        // still the most settled observation and remains subject to the seam gate.
        return latest
    }

    private func waitWhilePaused() async throws {
        while currentControl().isPaused {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func makeProgress(
        compositor: ScrollingCaptureCompositor,
        acceptedFrames: Int,
        rejectedFrames: Int,
        lastAlignment: ScrollingCaptureAlignment?
    ) -> ScrollingCaptureProgress {
        ScrollingCaptureProgress(
            acceptedFrameCount: acceptedFrames,
            rejectedFrameCount: rejectedFrames,
            outputPixelWidth: compositor.outputWidth,
            outputPixelHeight: compositor.outputHeight,
            lastAlignment: lastAlignment
        )
    }

    private func reserveStart() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !control.isRunning else {
            throw ScrollingCaptureAutoCaptureError.alreadyRunning
        }
        control = ControlState(isRunning: true)
    }

    private func install(task: Task<Void, Never>) {
        lock.lock()
        // A scripted/very small capture can finish before start() stores its task.
        // Do not resurrect a completed run in that race.
        if control.isRunning {
            captureTask = task
        }
        lock.unlock()
    }

    private func currentControl() -> ControlState {
        lock.lock()
        defer { lock.unlock() }
        return control
    }

    private func clearState() {
        lock.lock()
        control = ControlState()
        captureTask = nil
        lock.unlock()
    }
}
