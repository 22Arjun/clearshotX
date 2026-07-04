//
//  HotkeyOnboardingFlowViewModel.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import Combine
import Foundation
import OSLog

enum HotkeyOnboardingFlowContext {
    case firstRun
    case settings
}

enum HotkeyOnboardingScreen: String {
    case defaultScreenshotToolDecision
    case systemSettingsInstructions
    case nextOnboardingScreen
}

@MainActor
final class HotkeyOnboardingFlowViewModel: ObservableObject {
    typealias Handler = GlobalHotkeyService.Handler

    @Published private(set) var screen: HotkeyOnboardingScreen = .defaultScreenshotToolDecision
    @Published private(set) var inlineMessage: String?
    @Published private(set) var isWorking = false

    private let context: HotkeyOnboardingFlowContext
    private let hotkeyConflictResolutionManager: HotkeyConflictResolutionManager
    private let captureFullScreen: Handler
    private let captureRegion: Handler
    private let onHotkeyModeChanged: () -> Void
    private let onFinished: () -> Void
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "HotkeyOnboarding"
    )

    init(
        context: HotkeyOnboardingFlowContext,
        hotkeyConflictResolutionManager: HotkeyConflictResolutionManager,
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler,
        onHotkeyModeChanged: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.context = context
        self.hotkeyConflictResolutionManager = hotkeyConflictResolutionManager
        self.captureFullScreen = captureFullScreen
        self.captureRegion = captureRegion
        self.onHotkeyModeChanged = onHotkeyModeChanged
        self.onFinished = onFinished
    }

    var nextScreenTitle: String {
        switch context {
        case .firstRun:
            "Next onboarding screen"
        case .settings:
            "Keyboard shortcuts updated"
        }
    }

    var nextScreenSubtitle: String {
        switch context {
        case .firstRun:
            "This is a placeholder for Screen E. The rest of onboarding can continue from here."
        case .settings:
            "ClearshotX will keep using the shortcut choice you just selected."
        }
    }

    var nextScreenButtonTitle: String {
        switch context {
        case .firstRun:
            "Continue"
        case .settings:
            "Done"
        }
    }

    func declineDefaultShortcuts() {
        guard !isWorking else {
            return
        }

        logger.info("User selected independent screenshot shortcuts")
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            await hotkeyConflictResolutionManager.registerIndependentDefaultHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion
            )
            onHotkeyModeChanged()
            transition(to: .nextOnboardingScreen)
        }
    }

    func acceptDefaultShortcuts() {
        guard !isWorking else {
            return
        }

        logger.info("User selected macOS default screenshot shortcuts")
        inlineMessage = nil
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            await hotkeyConflictResolutionManager.prepareDefaultShortcutSetup(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion
            )
            onHotkeyModeChanged()
            transition(to: .systemSettingsInstructions)
        }
    }

    func openSystemSettings() {
        inlineMessage = nil

        guard hotkeyConflictResolutionManager.openKeyboardShortcutSettings() else {
            inlineMessage = "ClearshotX could not open System Settings automatically. Open Keyboard Shortcuts, then Screenshots, and turn off all five rows."
            return
        }

        logger.info("System Settings open request was accepted")
    }

    func returnToDefaultShortcutDecision() {
        inlineMessage = nil
        hotkeyConflictResolutionManager.cancelPendingDefaultShortcutSetup()
        transition(to: .defaultScreenshotToolDecision)
    }

    func confirmSystemShortcutsDisabled() {
        guard !isWorking else {
            return
        }

        inlineMessage = nil
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            let result = await hotkeyConflictResolutionManager.confirmDefaultShortcutSetup(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion
            )
            onHotkeyModeChanged()

            switch result {
            case .ready:
                transition(to: .nextOnboardingScreen)
            case .stillEnabled(let message):
                logger.info("User confirmation did not resolve the shortcut conflict")
                inlineMessage = message
            }
        }
    }

    func finish() {
        logger.info("Hotkey onboarding flow finished")
        onFinished()
    }

    private func transition(to nextScreen: HotkeyOnboardingScreen) {
        let previousScreen = screen
        screen = nextScreen
        logger.info("Hotkey onboarding transition \(previousScreen.rawValue, privacy: .public) -> \(nextScreen.rawValue, privacy: .public)")
    }
}
