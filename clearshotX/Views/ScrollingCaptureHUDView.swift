//
//  ScrollingCaptureHUDView.swift
//  clearshotX
//

import SwiftUI

/// Capture controls remain SwiftUI-driven; the rapidly changing page bitmap is
/// rendered directly by the layer-backed view in `ScrollingCaptureHUDManager`.
struct ScrollingCaptureControlsView: View {
    @ObservedObject var viewModel: ScrollingCaptureHUDViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.state.canStartCapture {
                Button {
                    viewModel.startCapture()
                } label: {
                    Label("Start Capture", systemImage: "record.circle")
                }
                .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: true))
                .help("Begin capturing as you scroll")
            } else {
                Button {
                    viewModel.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: false))

                Button {
                    viewModel.togglePause()
                } label: {
                    Image(
                        systemName: viewModel.state.pauseButtonTitle == "Resume"
                            ? "play.fill"
                            : "pause.fill"
                    )
                    .frame(width: 12, height: 12)
                }
                .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: false))
                .disabled(!viewModel.state.canPause)
                .help(viewModel.state.pauseButtonTitle)

                if viewModel.state.canSwitchToAutoScroll {
                    Button {
                        viewModel.switchToAutoScroll()
                    } label: {
                        Label("Auto Scroll", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: false))
                    .help("Switch to automatic scrolling")
                }

                Button {
                    viewModel.finish()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: true))
                .disabled(!viewModel.state.canFinish)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScrollingCapturePillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let emphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(emphasized ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                emphasized ? Color.white : Color.black.opacity(0.76),
                in: Capsule()
            )
            .opacity(!isEnabled ? 0.46 : (configuration.isPressed ? 0.72 : 1))
    }
}
