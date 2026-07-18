//
//  ScrollingCaptureCoordinator.swift
//  clearshotX
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScrollingCaptureCoordinator {
    typealias Completion = (Result<CaptureResult?, Error>) -> Void

    enum Phase: Equatable {
        case idle
        case starting
        case capturing
        case finishing
        case cancelling
    }

    private(set) var phase: Phase = .idle

    private let frameSource: ScrollingCaptureFrameSourcing
    private let captureStore: CaptureStoring
    private let hudPresenter: ScrollingCaptureHUDPresenting
    private let configuration: ScrollingCaptureConfiguration

    private var activeCaptureID: UUID?
    private var selectedRegion: CGRect?
    private var geometry: ScrollingCaptureRegionGeometry?
    private var worker: ScrollingCaptureWorker?
    private var completion: Completion?
    private var hudViewModel: ScrollingCaptureHUDViewModel?
    private var hudState: ScrollingCaptureHUDState = .starting
    private var consecutiveRejections = 0

    init(
        frameSource: ScrollingCaptureFrameSourcing = ScrollingCaptureFrameSource(),
        captureStore: CaptureStoring? = nil,
        hudPresenter: ScrollingCaptureHUDPresenting? = nil,
        configuration: ScrollingCaptureConfiguration = ScrollingCaptureConfiguration()
    ) {
        self.frameSource = frameSource
        self.captureStore = captureStore ?? CaptureStore()
        self.hudPresenter = hudPresenter ?? ScrollingCaptureHUDManager()
        self.configuration = configuration
    }

    func start(
        selectedRegion: CGRect,
        completion: @escaping Completion
    ) async throws {
        guard phase == .idle else {
            throw ScrollingCaptureFrameSourceError.alreadyRunning
        }

        let captureID = UUID()
        let worker = ScrollingCaptureWorker(configuration: configuration)
        let hudViewModel = ScrollingCaptureHUDViewModel(
            finish: { [weak self] in self?.finish() },
            cancel: { [weak self] in self?.cancel() }
        )

        activeCaptureID = captureID
        self.selectedRegion = selectedRegion
        self.worker = worker
        self.completion = completion
        self.hudViewModel = hudViewModel
        hudState = .starting
        consecutiveRejections = 0
        phase = .starting
        hudPresenter.show(viewModel: hudViewModel, adjacentTo: selectedRegion)

        do {
            let geometry = try await frameSource.start(
                selectedRegion: selectedRegion,
                onFrame: { [weak self, weak worker] frame in
                    guard let worker,
                          let result = worker.ingest(frame.image)
                    else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        self?.handle(result, captureID: captureID)
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleSourceFailure(error, captureID: captureID)
                    }
                }
            )

            guard activeCaptureID == captureID else {
                try? await frameSource.stop()
                return
            }

            self.geometry = geometry
            phase = .capturing
        } catch {
            guard activeCaptureID == captureID else { return }
            reset()
            throw error
        }
    }

    func finish() {
        guard phase == .capturing,
              let captureID = activeCaptureID
        else {
            return
        }
        finalize(captureID: captureID, stopSource: true, fallbackError: nil)
    }

    func cancel() {
        guard phase != .idle,
              phase != .cancelling,
              let captureID = activeCaptureID,
              let worker
        else {
            return
        }

        phase = .cancelling
        worker.cancel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.frameSource.stop()
            self.complete(.success(nil), captureID: captureID)
        }
    }

    private func handle(
        _ result: Result<ScrollingCaptureFrameDecision, Error>,
        captureID: UUID
    ) {
        guard activeCaptureID == captureID,
              phase == .capturing || phase == .starting
        else {
            return
        }

        switch result {
        case let .success(decision):
            hudState = ScrollingCaptureHUDReducer.applying(
                decision,
                to: hudState,
                consecutiveRejections: &consecutiveRejections
            )
            hudViewModel?.update(hudState)

            if case .reachedOutputLimit = decision {
                finalize(captureID: captureID, stopSource: true, fallbackError: nil)
            }

        case let .failure(error):
            finalize(captureID: captureID, stopSource: true, fallbackError: error)
        }
    }

    private func handleSourceFailure(_ error: Error, captureID: UUID) {
        guard activeCaptureID == captureID,
              phase != .finishing,
              phase != .cancelling
        else {
            return
        }
        finalize(captureID: captureID, stopSource: false, fallbackError: error)
    }

    private func finalize(
        captureID: UUID,
        stopSource: Bool,
        fallbackError: Error?
    ) {
        guard activeCaptureID == captureID,
              phase != .finishing,
              phase != .cancelling,
              let worker
        else {
            return
        }

        phase = .finishing
        hudState.phase = .finishing
        hudViewModel?.update(hudState)

        Task { @MainActor [weak self] in
            guard let self else { return }
            if stopSource {
                try? await self.frameSource.stop()
            }

            let assembledImage: Result<CGImage, Error> = await Task.detached(
                priority: .userInitiated
            ) {
                Result { try worker.finish() }
            }.value

            guard self.activeCaptureID == captureID else { return }

            switch assembledImage {
            case let .success(image):
                do {
                    let capture = try self.makeCaptureResult(
                        image: image,
                        selectedRegion: self.selectedRegion,
                        geometry: self.geometry
                    )
                    self.complete(.success(capture), captureID: captureID)
                } catch {
                    self.complete(.failure(error), captureID: captureID)
                }

            case let .failure(error):
                self.complete(
                    .failure(fallbackError ?? error),
                    captureID: captureID
                )
            }
        }
    }

    private func makeCaptureResult(
        image: CGImage,
        selectedRegion: CGRect?,
        geometry: ScrollingCaptureRegionGeometry?
    ) throws -> CaptureResult {
        let storedCapture = try captureStore.store(image)
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        return CaptureResult(
            image: nsImage,
            fileURL: storedCapture.fileURL,
            dragFileURL: storedCapture.dragFileURL,
            pixelWidth: image.width,
            pixelHeight: image.height,
            screenFrame: geometry?.displayFrame ?? selectedRegion ?? .zero
        )
    }

    private func complete(
        _ result: Result<CaptureResult?, Error>,
        captureID: UUID
    ) {
        guard activeCaptureID == captureID else { return }
        let completion = self.completion
        reset()
        completion?(result)
    }

    private func reset() {
        hudPresenter.dismiss()
        phase = .idle
        activeCaptureID = nil
        selectedRegion = nil
        geometry = nil
        worker = nil
        completion = nil
        hudViewModel = nil
        hudState = .starting
        consecutiveRejections = 0
    }
}

private nonisolated final class ScrollingCaptureWorker: @unchecked Sendable {
    private let lock = NSLock()
    private let session: ScrollingCaptureSession
    private var isActive = true

    init(configuration: ScrollingCaptureConfiguration) {
        session = ScrollingCaptureSession(configuration: configuration)
    }

    func ingest(
        _ image: CGImage
    ) -> Result<ScrollingCaptureFrameDecision, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { return nil }
        return Result { try session.ingest(image) }
    }

    func finish() throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { throw ScrollingCaptureError.noFrames }
        isActive = false
        return try session.finish()
    }

    func cancel() {
        lock.lock()
        isActive = false
        lock.unlock()
    }
}
