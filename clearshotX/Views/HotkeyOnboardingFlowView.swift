//
//  HotkeyOnboardingFlowView.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import SwiftUI

struct HotkeyOnboardingFlowView: View {
    @ObservedObject var viewModel: HotkeyOnboardingFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch viewModel.screen {
                case .defaultScreenshotToolDecision:
                    defaultScreenshotToolDecision
                case .systemSettingsInstructions:
                    systemSettingsInstructions
                case .nextOnboardingScreen:
                    nextOnboardingScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(width: 640, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: viewModel.screen)
    }

    private var defaultScreenshotToolDecision: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 52)

            screenshotKeycap

            Text("Set as default screenshot tool?")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 40)
                .padding(.horizontal, 56)

            Text("macOS currently owns the Screenshot shortcuts. ClearshotX can use ⇧⌘3 and ⇧⌘4 instead, or keep its own separate shortcuts.")
                .font(.system(size: 16))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .padding(.horizontal, 78)

            HStack(spacing: 10) {
                shortcutChip("⇧⌘3", "Full screen")
                shortcutChip("⇧⌘4", "Region")
            }
            .padding(.top, 30)

            Spacer(minLength: 44)

            Divider()

            HStack(spacing: 18) {
                Button("No, thanks") {
                    viewModel.declineDefaultShortcuts()
                }
                .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 132))
                .disabled(viewModel.isWorking)

                Button("Yes!") {
                    viewModel.acceptDefaultShortcuts()
                }
                .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 132))
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isWorking)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.thinMaterial)
        }
    }

    private var systemSettingsInstructions: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 42)

            systemSettingsGraphic

            Text("One quick step in System Settings")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 34)
                .padding(.horizontal, 56)

            Text("Turn off all five macOS Screenshots shortcuts, then come back here and confirm.")
                .font(.system(size: 16))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .padding(.horizontal, 76)

            Button {
                viewModel.openSystemSettings()
            } label: {
                Label("Open System Settings", systemImage: "gearshape")
            }
            .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 190))
            .padding(.top, 30)
            .disabled(viewModel.isWorking)

            if let inlineMessage = viewModel.inlineMessage {
                Text(inlineMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                    .padding(.horizontal, 88)
            } else {
                Spacer(minLength: 51)
            }

            Spacer(minLength: 22)

            Divider()

            HStack(spacing: 18) {
                Button("Back") {
                    viewModel.returnToDefaultShortcutDecision()
                }
                .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 122))
                .disabled(viewModel.isWorking)

                Button {
                    viewModel.confirmSystemShortcutsDisabled()
                } label: {
                    if viewModel.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    } else {
                        Text("I turned it off")
                    }
                }
                .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 148))
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isWorking)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.thinMaterial)
        }
    }

    private var nextOnboardingScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 64)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .frame(width: 100, height: 100)

            Text(viewModel.nextScreenTitle)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 32)
                .padding(.horizontal, 56)

            Text(viewModel.nextScreenSubtitle)
                .font(.system(size: 16))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .padding(.horizontal, 88)

            Spacer(minLength: 56)

            Divider()

            HStack {
                Button(viewModel.nextScreenButtonTitle) {
                    viewModel.finish()
                }
                .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 132))
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.thinMaterial)
        }
    }

    private var screenshotKeycap: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Text("cmd")
                .font(.system(size: 24))
                .baselineOffset(3)

            Text("⌘")
                .font(.system(size: 42, weight: .semibold))
        }
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .frame(width: 126, height: 96)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: -1)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 15)
        )
    }

    private var systemSettingsGraphic: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 126, height: 96)
                .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: -1)
                .shadow(color: .black.opacity(0.13), radius: 16, x: 0, y: 14)

            Image(systemName: "keyboard")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(width: 126, height: 96)
    }

    private func shortcutChip(_ shortcut: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            Text(shortcut)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: .labelColor))

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

private struct OnboardingActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: width, height: 36)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(kind == .primary ? 0.12 : 0.08), radius: 3, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            Color(nsColor: isPressed ? .systemBlue.withSystemEffect(.pressed) : .systemBlue)
        case .secondary:
            Color(nsColor: isPressed ? .systemGray.withSystemEffect(.pressed) : .systemGray)
        }
    }
}
