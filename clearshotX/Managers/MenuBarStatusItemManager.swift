//
//  MenuBarStatusItemManager.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit

@MainActor
final class MenuBarStatusItemManager: NSObject, NSMenuDelegate {
    private let menu = NSMenu()

    private var statusItem: NSStatusItem?
    private weak var viewModel: AppShellViewModel?

    func configure(viewModel: AppShellViewModel) {
        self.viewModel = viewModel
        menu.delegate = self
    }

    func show(onReady: ((NSStatusBarButton?, NSRect?) -> Void)? = nil) {
        let statusItem = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ClearshotX")
            button.imagePosition = .imageOnly
            button.toolTip = "ClearshotX"
        }

        statusItem.menu = menu

        if let onReady {
            notifyWhenStatusItemFrameIsReady(onReady)
        }
    }

    func hide() {
        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func statusItemFrameInScreen() -> NSRect? {
        guard let button = statusItem?.button,
              let window = button.window
        else {
            return nil
        }

        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func statusItemButton() -> NSStatusBarButton? {
        statusItem?.button
    }

    private func notifyWhenStatusItemFrameIsReady(
        _ onReady: @escaping (NSStatusBarButton?, NSRect?) -> Void,
        attempt: Int = 0
    ) {
        if let button = statusItemButton(), let frame = statusItemFrameInScreen() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onReady(button, frame)
            }
            return
        }

        guard attempt < 10 else {
            onReady(statusItemButton(), nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            Task { @MainActor [weak self] in
                self?.notifyWhenStatusItemFrameIsReady(onReady, attempt: attempt + 1)
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        menu.addItem(
            item(
                title: title("Capture Full Screen", action: .captureFullScreen),
                systemImage: "rectangle.inset.filled",
                action: #selector(captureFullScreen),
                isEnabled: viewModel?.isCapturing == false
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            item(
                title: title("Capture Region", action: .captureRegion),
                systemImage: "selection.pin.in.out",
                action: #selector(captureRegion),
                isEnabled: viewModel?.isCapturing == false
            )
        )
        menu.addItem(
            item(
                title: "Capture Window",
                systemImage: "macwindow",
                action: #selector(captureWindow),
                isEnabled: viewModel?.isCapturing == false
            )
        )
        menu.addItem(
            item(
                title: "Capture Scrolling Region",
                systemImage: "arrow.down.to.line.compact",
                action: #selector(captureScrollingRegion),
                isEnabled: viewModel?.isCapturing == false
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            item(
                title: "Screen Recording Permission",
                systemImage: "lock.shield",
                action: #selector(openScreenRecordingSettings)
            )
        )
        menu.addItem(
            item(
                title: "Settings",
                systemImage: "gearshape",
                action: #selector(openSettings)
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            item(
                title: "Quit ClearshotX",
                systemImage: "power",
                action: #selector(quit)
            )
        )
    }

    private func item(
        title: String,
        systemImage: String,
        action: Selector,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        return item
    }

    private func title(_ baseTitle: String, action: GlobalHotkeyAction) -> String {
        guard let shortcut = viewModel?.shortcutLabel(for: action), !shortcut.isEmpty else {
            return baseTitle
        }

        return "\(baseTitle) (\(shortcut))"
    }

    @objc private func captureFullScreen() {
        viewModel?.captureFullScreen()
    }

    @objc private func captureRegion() {
        viewModel?.captureRegion()
    }

    @objc private func captureWindow() {
        viewModel?.captureWindow()
    }

    @objc private func captureScrollingRegion() {
        viewModel?.captureScrollingRegion()
    }

    @objc private func openScreenRecordingSettings() {
        viewModel?.openScreenRecordingSettings()
    }

    @objc private func openSettings() {
        viewModel?.openSettings()
    }

    @objc private func quit() {
        viewModel?.quit()
    }
}
