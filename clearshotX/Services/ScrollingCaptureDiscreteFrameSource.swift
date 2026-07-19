//
//  ScrollingCaptureDiscreteFrameSource.swift
//  clearshotX
//

import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Captures one exact native-resolution viewport on demand. The filter and stream
/// configuration are prepared once and reused for every auto-scroll step.
nonisolated final class ScrollingCaptureDiscreteFrameSource:
    ScrollingCaptureDiscreteFrameSourcing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var filter: SCContentFilter?
    private var streamConfiguration: SCStreamConfiguration?
    private var geometry: ScrollingCaptureRegionGeometry?

    func prepare(
        selectedRegion: CGRect
    ) async throws -> ScrollingCaptureRegionGeometry {
        let content = try await SCShareableContent.current
        let descriptors = NSScreen.screens.compactMap {
            screen -> ScrollingCaptureDisplayDescriptor? in
            guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else {
                return nil
            }
            return ScrollingCaptureDisplayDescriptor(
                displayID: displayID,
                frame: screen.frame,
                pointPixelScale: screen.backingScaleFactor
            )
        }
        let geometry = try ScrollingCaptureRegionResolver.resolve(
            selectedRegion: selectedRegion,
            displays: descriptors
        )
        guard let display = content.displays.first(where: {
            $0.displayID == geometry.displayID
        }) else {
            throw ScrollingCaptureFrameSourceError.selectedDisplayUnavailable
        }

        let excludedApplications = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        filter.includeMenuBar = true

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect
        configuration.width = geometry.pixelWidth
        configuration.height = geometry.pixelHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        configuration.shouldBeOpaque = true

        installPreparedState(
            filter: filter,
            configuration: configuration,
            geometry: geometry
        )
        return geometry
    }

    func captureFrame() async throws -> CGImage {
        let state = preparedState()
        guard let filter = state.filter,
              let configuration = state.configuration,
              let geometry = state.geometry else {
            throw ScrollingCaptureAutoCaptureError.notPrepared
        }
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard image.width == geometry.pixelWidth,
              image.height == geometry.pixelHeight else {
            throw ScrollingCaptureError.inconsistentFrameSize(
                expected: CGSize(width: geometry.pixelWidth, height: geometry.pixelHeight),
                actual: CGSize(width: image.width, height: image.height)
            )
        }
        return image
    }

    func stop() async {
        clearPreparedState()
    }

    private func installPreparedState(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        geometry: ScrollingCaptureRegionGeometry
    ) {
        lock.lock()
        self.filter = filter
        streamConfiguration = configuration
        self.geometry = geometry
        lock.unlock()
    }

    private func clearPreparedState() {
        lock.lock()
        filter = nil
        streamConfiguration = nil
        geometry = nil
        lock.unlock()
    }

    private func preparedState() -> (
        filter: SCContentFilter?,
        configuration: SCStreamConfiguration?,
        geometry: ScrollingCaptureRegionGeometry?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (filter, streamConfiguration, geometry)
    }
}

/// Posts continuous pixel-wheel events at the selection center. CGEvent uses a
/// top-left desktop origin while AppKit selection geometry uses bottom-left.
nonisolated final class ScrollingCaptureCGEventScrollDriver:
    ScrollingCaptureScrollDriving,
    @unchecked Sendable
{
    private let eventSource = CGEventSource(stateID: .combinedSessionState)

    func scroll(verticalDelta: Int, at appKitPoint: CGPoint) throws {
        guard verticalDelta != 0 else { return }
        guard CGPreflightPostEventAccess() else {
            throw ScrollingCaptureAutoCaptureError.postEventPermissionDenied
        }
        // The first screen owns the AppKit global origin/menu bar. Using its top
        // preserves correct Quartz coordinates for displays above or below it.
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? appKitPoint.y
        let quartzPoint = CGPoint(
            x: appKitPoint.x,
            y: desktopTop - appKitPoint.y
        )
        let wheelDelta = Int32(clamping: -verticalDelta)
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: wheelDelta,
            wheel2: 0,
            wheel3: 0
        ) else {
            throw ScrollingCaptureAutoCaptureError.eventCreationFailed
        }
        event.location = quartzPoint
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: Int64(wheelDelta)
        )
        event.post(tap: .cghidEventTap)
    }
}
