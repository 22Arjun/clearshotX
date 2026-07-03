//
//  ContentViewModel.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ContentViewModel: ObservableObject {
    @Published private(set) var latestCapture: CaptureResult?
    @Published private(set) var isCapturing = false
    @Published var alertMessage: String?

    private let screenCaptureService: ScreenCaptureService

    init(screenCaptureService: ScreenCaptureService? = nil) {
        self.screenCaptureService = screenCaptureService ?? ScreenCaptureService()
    }

    var hasCapture: Bool {
        latestCapture != nil
    }

    func captureFullScreen() {
        guard !isCapturing else {
            return
        }

        isCapturing = true
        alertMessage = nil

        Task {
            defer {
                isCapturing = false
            }

            do {
                latestCapture = try await screenCaptureService.captureFullScreen()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func copyLatestCaptureToClipboard() {
        guard let image = latestCapture?.image else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func openScreenRecordingSettings() {
        screenCaptureService.openScreenRecordingSettings()
    }
}
