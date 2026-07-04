//
//  MacScreenshotShortcutService.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import Foundation
import OSLog

struct MacScreenshotShortcutConflict: Identifiable {
    let id: String
    let hotkey: GlobalHotkey
    let systemShortcutName: String
}

struct MacScreenshotShortcutStatus: Identifiable {
    let id: String
    let systemShortcutName: String
    let shortcutDisplayName: String
    let isEnabled: Bool
}

enum MacScreenshotShortcutState {
    case allDisabled
    case active(conflicts: [MacScreenshotShortcutConflict])
    case unknown
}

final class MacScreenshotShortcutService {
    private struct SystemShortcut {
        let symbolicHotkeyID: String
        let name: String
        let hotkey: GlobalHotkey
    }

    private struct ShortcutPreferenceSource {
        let name: String
        let shortcutsDictionary: [String: Any]
    }

    private static let shortcuts: [SystemShortcut] = [
        SystemShortcut(
            symbolicHotkeyID: "28",
            name: "Save picture of screen as a file",
            hotkey: GlobalHotkeyService.systemScreenshotHotkeys[0]
        ),
        SystemShortcut(
            symbolicHotkeyID: "29",
            name: "Copy picture of screen to the clipboard",
            hotkey: GlobalHotkeyService.systemScreenshotHotkeys[3]
        ),
        SystemShortcut(
            symbolicHotkeyID: "30",
            name: "Save picture of selected area as a file",
            hotkey: GlobalHotkeyService.systemScreenshotHotkeys[1]
        ),
        SystemShortcut(
            symbolicHotkeyID: "31",
            name: "Copy picture of selected area to the clipboard",
            hotkey: GlobalHotkeyService.systemScreenshotHotkeys[4]
        ),
        SystemShortcut(
            symbolicHotkeyID: "184",
            name: "Screenshot and recording options",
            hotkey: GlobalHotkeyService.systemScreenshotHotkeys[2]
        )
    ]

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "MacScreenshotShortcuts"
    )

    func screenshotShortcutState() -> MacScreenshotShortcutState {
        let preferenceSources = screenshotShortcutPreferenceSources()

        guard !preferenceSources.isEmpty else {
            logger.warning("Could not read AppleSymbolicHotKeys")
            return .unknown
        }

        var missingShortcutIDsBySource: [String] = []

        for preferenceSource in preferenceSources {
            let result = evaluateShortcutState(
                shortcutsDictionary: preferenceSource.shortcutsDictionary
            )

            guard result.missingShortcutIDs.isEmpty else {
                missingShortcutIDsBySource.append(
                    "\(preferenceSource.name): \(result.missingShortcutIDs.joined(separator: ","))"
                )
                continue
            }

            switch result.state {
            case .allDisabled:
                logger.info("All tracked macOS screenshot shortcuts are disabled in \(preferenceSource.name, privacy: .public)")
            case .active(let conflicts):
                logger.info("Tracked macOS screenshot shortcuts still enabled in \(preferenceSource.name, privacy: .public): \(conflicts.map(\.id).joined(separator: ","), privacy: .public)")
            case .unknown:
                logger.warning("Could not evaluate macOS screenshot shortcuts in \(preferenceSource.name, privacy: .public)")
            }

            return result.state
        }

        logger.warning("Could not read complete enabled state for screenshot shortcuts. Missing IDs by source: \(missingShortcutIDsBySource.joined(separator: " | "), privacy: .public)")
        return .unknown
    }

    private func evaluateShortcutState(
        shortcutsDictionary: [String: Any]
    ) -> (state: MacScreenshotShortcutState, missingShortcutIDs: [String]) {
        var conflicts: [MacScreenshotShortcutConflict] = []
        var missingShortcutIDs: [String] = []

        for shortcut in Self.shortcuts {
            guard let entry = dictionaryValue(shortcutsDictionary[shortcut.symbolicHotkeyID]),
                  let isEnabled = booleanValue(entry["enabled"])
            else {
                missingShortcutIDs.append(shortcut.symbolicHotkeyID)
                continue
            }

            guard isEnabled else {
                continue
            }

            conflicts.append(
                MacScreenshotShortcutConflict(
                    id: shortcut.symbolicHotkeyID,
                    hotkey: shortcut.hotkey,
                    systemShortcutName: shortcut.name
                )
            )
        }

        guard missingShortcutIDs.isEmpty else {
            return (.unknown, missingShortcutIDs)
        }

        if conflicts.isEmpty {
            return (.allDisabled, [])
        }

        return (.active(conflicts: conflicts), [])
    }

    func activeScreenshotShortcutConflicts() -> [MacScreenshotShortcutConflict] {
        switch screenshotShortcutState() {
        case .allDisabled:
            return []
        case .unknown:
            return fallbackConflicts()
        case .active(let conflicts):
            return conflicts
        }
    }

    func screenshotShortcutStatuses(for state: MacScreenshotShortcutState) -> [MacScreenshotShortcutStatus]? {
        switch state {
        case .allDisabled:
            return Self.shortcuts.map { shortcut in
                MacScreenshotShortcutStatus(
                    id: shortcut.symbolicHotkeyID,
                    systemShortcutName: shortcut.name,
                    shortcutDisplayName: shortcut.hotkey.displayName,
                    isEnabled: false
                )
            }
        case .active(let conflicts):
            let enabledShortcutIDs = Set(conflicts.map(\.id))

            return Self.shortcuts.map { shortcut in
                MacScreenshotShortcutStatus(
                    id: shortcut.symbolicHotkeyID,
                    systemShortcutName: shortcut.name,
                    shortcutDisplayName: shortcut.hotkey.displayName,
                    isEnabled: enabledShortcutIDs.contains(shortcut.symbolicHotkeyID)
                )
            }
        case .unknown:
            return nil
        }
    }

    private func screenshotShortcutPreferenceSources() -> [ShortcutPreferenceSource] {
        let applicationID = "com.apple.symbolichotkeys" as CFString
        var preferenceSources: [ShortcutPreferenceSource] = []

        let valueQueries: [(name: String, userName: CFString, hostName: CFString)] = [
            ("CurrentUser/AnyHost", kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
            ("CurrentUser/CurrentHost", kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        ]

        for query in valueQueries {
            CFPreferencesSynchronize(applicationID, query.userName, query.hostName)

            let value = CFPreferencesCopyValue(
                "AppleSymbolicHotKeys" as CFString,
                applicationID,
                query.userName,
                query.hostName
            )

            if let dictionary = dictionaryValue(value) {
                preferenceSources.append(
                    ShortcutPreferenceSource(
                        name: "CFPreferences \(query.name)",
                        shortcutsDictionary: dictionary
                    )
                )
            }
        }

        CFPreferencesAppSynchronize(applicationID)

        let appValue = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            applicationID
        )

        if let dictionary = dictionaryValue(appValue) {
            preferenceSources.append(
                ShortcutPreferenceSource(
                    name: "CFPreferences app value",
                    shortcutsDictionary: dictionary
                )
            )
        }

        if let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
           let dictionary = dictionaryValue(domain["AppleSymbolicHotKeys"]) {
            preferenceSources.append(
                ShortcutPreferenceSource(
                    name: "UserDefaults persistent domain",
                    shortcutsDictionary: dictionary
                )
            )
        }

        return preferenceSources
    }

    private func fallbackConflicts() -> [MacScreenshotShortcutConflict] {
        Self.shortcuts.map { shortcut in
            MacScreenshotShortcutConflict(
                id: shortcut.symbolicHotkeyID,
                hotkey: shortcut.hotkey,
                systemShortcutName: shortcut.name
            )
        }
    }

    private func dictionaryValue(_ value: Any?) -> [String: Any]? {
        guard let value = value as? NSDictionary else {
            return nil
        }

        var normalizedDictionary: [String: Any] = [:]

        for (key, nestedValue) in value {
            if let key = key as? String {
                normalizedDictionary[key] = nestedValue
            } else if let key = key as? NSNumber {
                normalizedDictionary[key.stringValue] = nestedValue
            }
        }

        return normalizedDictionary
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? Int {
            return value != 0
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    @discardableResult
    func openKeyboardShortcutSettings() -> Bool {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
        ]

        for urlString in urlStrings {
            guard let url = URL(string: urlString) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        return false
    }
}
