//
//  ScreenRecordingPermissionService.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import CoreGraphics
import Foundation
import OSLog

enum ScreenRecordingPermissionState: Equatable {
    case granted
    case notGranted
}

@MainActor
final class ScreenRecordingPermissionService {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "ScreenRecordingPermission"
    )

    func currentState() async -> ScreenRecordingPermissionState {
        let isGranted = CGPreflightScreenCaptureAccess()
        logger.info("Screen Recording permission preflight returned \(isGranted, privacy: .public)")
        return isGranted ? .granted : .notGranted
    }

    @discardableResult
    func requestPermission() async -> ScreenRecordingPermissionState {
        logger.info("Requesting Screen Recording permission")
        let requestResult = CGRequestScreenCaptureAccess()
        logger.info("Screen Recording permission request returned \(requestResult, privacy: .public)")
        return await currentState()
    }

    @discardableResult
    func openSystemSettings() -> Bool {
        logger.info("Opening Screen Recording privacy pane")

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            logger.error("Could not build Screen Recording privacy pane URL")
            return false
        }

        let didOpen = NSWorkspace.shared.open(url)
        logger.info("Screen Recording privacy pane open request returned \(didOpen, privacy: .public)")
        return didOpen
    }
}
