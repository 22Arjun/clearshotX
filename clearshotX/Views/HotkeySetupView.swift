//
//  HotkeySetupView.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import SwiftUI

struct HotkeySetupView: View {
    let hasActiveSystemShortcuts: Bool
    let onAcceptDefaultShortcuts: () -> Void
    let onDeclineDefaultShortcuts: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 58)

                keycap
                    .scaleEffect(appeared ? 1 : 0.92)
                    .offset(y: appeared ? 0 : 10)
                    .opacity(appeared ? 1 : 0)

                Spacer(minLength: 54)

                Text("Set as default screenshot tool?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 44)
                    .offset(y: appeared ? 0 : 8)
                    .opacity(appeared ? 1 : 0)

                Text(subtitle)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.horizontal, 82)
                    .offset(y: appeared ? 0 : 8)
                    .opacity(appeared ? 1 : 0)

                HStack(spacing: 10) {
                    shortcutChip("⇧⌘3", "Full screen")
                    shortcutChip("⇧⌘4", "Region")
                }
                .padding(.top, 32)
                .offset(y: appeared ? 0 : 8)
                .opacity(appeared ? 1 : 0)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 24) {
                Button("No, thanks") {
                    onDeclineDefaultShortcuts()
                }
                .buttonStyle(SetupDecisionButtonStyle(kind: .secondary))

                Button("Yes!") {
                    onAcceptDefaultShortcuts()
                }
                .buttonStyle(SetupDecisionButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.thinMaterial)
            .offset(y: appeared ? 0 : 12)
            .opacity(appeared ? 1 : 0)
        }
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var keycap: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Text("cmd")
                .font(.system(size: 25, weight: .regular))
                .baselineOffset(3)

            Text("⌘")
                .font(.system(size: 44, weight: .semibold))
        }
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .frame(width: 128, height: 98)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: -1)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 16)
        )
    }

    private var subtitle: String {
        if hasActiveSystemShortcuts {
            "Do you want to assign ⇧⌘3 and ⇧⌘4 shortcuts to ClearshotX? Fallback shortcuts stay active now, and you can finish the system shortcut setup later from ClearshotX settings."
        } else {
            "Do you want to assign ⇧⌘3 and ⇧⌘4 shortcuts to ClearshotX as your default screenshot workflow?"
        }
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

private struct SetupDecisionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 132, height: 36)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(kind == .primary ? 0.12 : 0.08), radius: 3, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            .white
        case .secondary:
            .white
        }
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
