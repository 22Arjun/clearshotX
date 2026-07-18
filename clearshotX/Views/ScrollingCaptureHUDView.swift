//
//  ScrollingCaptureHUDView.swift
//  clearshotX
//

import SwiftUI

struct ScrollingCaptureHUDView: View {
    @ObservedObject var viewModel: ScrollingCaptureHUDViewModel

    var body: some View {
        HStack(spacing: 14) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(viewModel.state.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    if let dimensions = viewModel.state.dimensionsText {
                        Text(dimensions)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                }

                Text(viewModel.state.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button("Cancel") {
                    viewModel.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Finish") {
                    viewModel.finish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!viewModel.state.canFinish)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: 520, height: 82)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .padding(20)
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.16))
                .frame(width: 36, height: 36)

            if viewModel.state.phase == .starting || viewModel.state.phase == .finishing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: viewModel.state.phase == .guidance
                    ? "speedometer"
                    : "arrow.down.to.line.compact")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var iconColor: Color {
        viewModel.state.phase == .guidance ? .orange : .accentColor
    }
}
