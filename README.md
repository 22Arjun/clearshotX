# ClearshotX

ClearshotX is a native macOS screen capture utility designed for fast screenshots, screen recording, annotation, OCR, and lightweight capture management.

The app is built as a menu-bar-resident macOS tool: it should stay out of the Dock, remain available in the background, and expose capture actions through a menu bar icon and global keyboard shortcuts. Capture windows, preview panels, editors, and settings appear only when the user asks for them.

ClearshotX is an independent project inspired by modern macOS screenshot workflows. It is not affiliated with CleanShot X or its creators.

## Vision

ClearshotX aims to become a polished, native replacement for the default macOS screenshot flow. The goal is to make capturing, marking up, copying, saving, and sharing visual context feel immediate.

The intended experience is:

1. Launch ClearshotX once.
2. Use the menu bar icon or a global shortcut whenever a capture is needed.
3. Capture the full screen, a selected region, a window, or a recording.
4. See an instant preview overlay.
5. Copy, save, drag, annotate, extract text, or keep the capture for later.

## Current Status

ClearshotX is in early development.

Currently implemented:

- Native macOS Xcode project
- SwiftUI prototype interface
- Full-screen screenshot capture using `ScreenCaptureKit`
- Screen Recording permission check and settings shortcut
- PNG export to the app's Application Support directory
- Screenshot preview inside the prototype UI
- Copy latest capture to the clipboard
- MVVM-oriented folder structure for models, services, and view models

In progress / next correction:

- Convert the prototype launch window into a true menu-bar-only app shell
- Add `MenuBarExtra` with capture actions
- Hide Dock and Cmd+Tab presence using macOS accessory activation behavior
- Show preview/editor windows only after a capture

## Planned Features

### Capture

- Full-screen screenshot
- Region selection screenshot
- Window screenshot
- Self-timer capture
- Scrolling capture
- Capture without desktop clutter

### Recording

- Full-screen, window, and region recording
- Optional microphone and system audio
- Optional webcam bubble overlay
- Floating recording controls
- Export to common video formats

### Annotation

- Instant post-capture preview
- Arrows, rectangles, freehand drawing, and text labels
- Blur and redaction tools
- Highlighting
- Undo and redo
- Copy or save annotated output

### OCR

- Extract text from screenshots using Apple's Vision framework
- Copy recognized text to the clipboard
- Store recognized text as searchable metadata later

### Pins

- Pin screenshots as floating always-on-top desktop references
- Resize and adjust opacity
- Keep visual references available while working in other apps

### Library

- Browse recent screenshots and recordings
- Open, copy, delete, or reuse previous captures
- Start with `FileManager` storage before introducing any database

### Settings

- Configurable global shortcuts
- Default save location
- Auto-copy behavior
- Show or hide preview after capture
- Capture sound toggle
- Privacy and permissions state

## Product Shape

ClearshotX is not intended to behave like a traditional document-based desktop app.

The core shell should be:

- Menu bar icon as the primary entry point
- No main window on launch
- No Dock icon in normal use
- No Cmd+Tab entry in normal use
- Background utility lifecycle
- On-demand panels for capture, preview, editor, history, and settings

This design keeps ClearshotX available without interrupting the user's workspace.

## Tech Stack

- **Language:** Swift 6
- **UI:** SwiftUI for settings, preferences, history, and general views
- **App shell:** `MenuBarExtra`, `NSWindow`, and `NSPanel`
- **macOS behavior:** AppKit for menu bar integration, windows, panels, overlays, and precise event handling
- **Capture:** ScreenCaptureKit
- **Fallback capture:** CoreGraphics where needed
- **Recording:** ScreenCaptureKit and AVFoundation
- **Graphics:** CoreGraphics, CoreImage, and CoreAnimation
- **OCR:** Vision framework
- **Hotkeys:** KeyboardShortcuts by Sindre Sorhus, via Swift Package Manager
- **Storage:** FileManager for captures, UserDefaults for preferences
- **Clipboard and drag/drop:** NSPasteboard, NSDraggingSession, UniformTypeIdentifiers
- **Concurrency:** async/await, Task, and actors where appropriate
- **Logging:** OSLog
- **Distribution:** Direct download first, with Developer ID signing, notarization, and Sparkle later

## Architecture

ClearshotX follows an MVVM-oriented native macOS architecture.

Project folders:

- `App` - app lifecycle, menu bar shell, routing, and window coordination
- `Views` - SwiftUI and AppKit-backed user interfaces
- `ViewModels` - UI state and view-facing actions
- `Services` - capture, recording, OCR, export, storage, and permissions logic
- `Managers` - coordination objects for windows, panels, hotkeys, and app-level flows
- `Models` - plain data structures
- `Utilities` - shared helpers
- `Extensions` - small focused language or framework extensions
- `Resources` - assets and bundled resources

Guidelines:

- Views should stay lightweight.
- Business logic belongs in services or managers.
- View models expose state and call services.
- Prefer dependency injection over global singletons.
- Keep features testable as the app grows.

## Development Priorities

Immediate priorities:

1. Menu-bar-only app shell
2. Full-screen capture from the menu bar
3. Region capture
4. Window capture
5. Instant preview window after capture
6. Copy and save actions
7. Basic annotation tools
8. Global hotkeys

Later priorities:

- Screen recording
- OCR
- Capture history
- Desktop pins
- Scrolling capture
- Cloud sharing
- Auto-updates

## Requirements

- macOS 14 or newer recommended
- Xcode
- Screen Recording permission for capture features

Some APIs used by ClearshotX require modern macOS versions. The deployment target may be adjusted as the app settles on its final minimum supported OS.

## Building

Open the Xcode project:

```bash
open clearshotX.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -project clearshotX.xcodeproj -scheme clearshotX -configuration Debug build
```

When running capture features for the first time, macOS may ask for Screen Recording permission. After granting permission, the app may need to be restarted.

## Repository Notes

This repository is currently in early product development. The capture engine is being built first, but the intended final shape is a menu-bar utility, not a normal window-first macOS app.

Screenshots and videos will be added once the app shell and preview workflow are stable.

## License

License information has not been finalized yet.
