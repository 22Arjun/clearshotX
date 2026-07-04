//
//  GlobalHotkeyService.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import Carbon
import Foundation
import OSLog

enum GlobalHotkeyAction: UInt32, CaseIterable {
    case captureFullScreen = 1
    case captureRegion = 2
    case captureWindow = 3
    case allInOne = 4
}

enum GlobalHotkeyMode: String {
    case preferred
    case temporary
    case menuBarOnly
}

struct GlobalHotkey {
    let action: GlobalHotkeyAction
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String
}

struct GlobalHotkeyRegistrationFailure: Error, Identifiable {
    let hotkey: GlobalHotkey
    let status: OSStatus

    var id: UInt32 {
        hotkey.action.rawValue
    }
}

struct GlobalHotkeyRegistrationResult {
    let mode: GlobalHotkeyMode
    let registeredHotkeys: [GlobalHotkey]
    let failures: [GlobalHotkeyRegistrationFailure]

    var isSuccessful: Bool {
        failures.isEmpty
    }
}

final class GlobalHotkeyService {
    typealias Handler = @MainActor () -> Void

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "GlobalHotkeys"
    )

    static let preferredHotkeys: [GlobalHotkey] = [
        GlobalHotkey(
            action: .captureFullScreen,
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: UInt32(cmdKey | shiftKey),
            displayName: "⇧⌘3"
        ),
        GlobalHotkey(
            action: .captureRegion,
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(cmdKey | shiftKey),
            displayName: "⇧⌘4"
        )
    ]

    static let systemScreenshotHotkeys: [GlobalHotkey] = [
        GlobalHotkey(
            action: .captureFullScreen,
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: UInt32(cmdKey | shiftKey),
            displayName: "⇧⌘3"
        ),
        GlobalHotkey(
            action: .captureRegion,
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(cmdKey | shiftKey),
            displayName: "⇧⌘4"
        ),
        GlobalHotkey(
            action: .allInOne,
            keyCode: UInt32(kVK_ANSI_5),
            modifiers: UInt32(cmdKey | shiftKey),
            displayName: "⇧⌘5"
        ),
        GlobalHotkey(
            action: .captureFullScreen,
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: UInt32(cmdKey | controlKey | shiftKey),
            displayName: "⌃⇧⌘3"
        ),
        GlobalHotkey(
            action: .captureRegion,
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(cmdKey | controlKey | shiftKey),
            displayName: "⌃⇧⌘4"
        )
    ]

    static let temporaryHotkeys: [GlobalHotkey] = [
        GlobalHotkey(
            action: .captureFullScreen,
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(controlKey | shiftKey),
            displayName: "Ctrl+Shift+1"
        ),
        GlobalHotkey(
            action: .captureRegion,
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: UInt32(controlKey | shiftKey),
            displayName: "Ctrl+Shift+2"
        )
    ]

    private static weak var activeService: GlobalHotkeyService?
    private static let signature = GlobalHotkeyService.fourCharacterCode("CLSX")

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [GlobalHotkeyAction: EventHotKeyRef] = [:]
    private var handlers: [GlobalHotkeyAction: Handler] = [:]

    deinit {
        unregisterAll()
    }

    func register(
        mode: GlobalHotkeyMode,
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) -> GlobalHotkeyRegistrationResult {
        unregisterAll()

        handlers = [
            .captureFullScreen: captureFullScreen,
            .captureRegion: captureRegion
        ]

        Self.activeService = self
        installEventHandlerIfNeeded()

        let hotkeys = hotkeys(for: mode)
        var registeredHotkeys: [GlobalHotkey] = []
        var failures: [GlobalHotkeyRegistrationFailure] = []

        for hotkey in hotkeys {
            switch registerHotkey(hotkey) {
            case .success:
                registeredHotkeys.append(hotkey)
            case .failure(let failure):
                failures.append(failure)
            }
        }

        if !failures.isEmpty {
            for hotkeyRef in hotkeyRefs.values {
                UnregisterEventHotKey(hotkeyRef)
            }

            hotkeyRefs.removeAll()
            registeredHotkeys.removeAll()
        }

        return GlobalHotkeyRegistrationResult(
            mode: mode,
            registeredHotkeys: registeredHotkeys,
            failures: failures
        )
    }

    func unregisterAll() {
        for hotkeyRef in hotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }

        hotkeyRefs.removeAll()
        handlers.removeAll()

        if Self.activeService === self {
            Self.activeService = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotkeyEvent,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )
    }

    private func hotkeys(for mode: GlobalHotkeyMode) -> [GlobalHotkey] {
        switch mode {
        case .preferred:
            Self.preferredHotkeys
        case .temporary:
            Self.temporaryHotkeys
        case .menuBarOnly:
            []
        }
    }

    private func registerHotkey(_ hotkey: GlobalHotkey) -> Result<Void, GlobalHotkeyRegistrationFailure> {
        let hotkeyID = EventHotKeyID(
            signature: Self.signature,
            id: hotkey.action.rawValue
        )
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            logger.warning("Failed to register global hotkey \(hotkey.displayName, privacy: .public). OSStatus: \(status)")
            return .failure(GlobalHotkeyRegistrationFailure(hotkey: hotkey, status: status))
        }

        hotkeyRefs[hotkey.action] = hotkeyRef
        return .success(())
    }

    private func perform(action: GlobalHotkeyAction) {
        guard let handler = handlers[action] else {
            return
        }

        Task { @MainActor in
            handler()
        }
    }

    private static let handleHotkeyEvent: EventHandlerUPP = { _, eventRef, _ in
        guard let eventRef else {
            return OSStatus(eventNotHandledErr)
        }

        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr,
              hotkeyID.signature == GlobalHotkeyService.signature,
              let action = GlobalHotkeyAction(rawValue: hotkeyID.id)
        else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async {
            GlobalHotkeyService.activeService?.perform(action: action)
        }

        return noErr
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
