//
//  ContentView.swift
//  clearshotX
//
//  Created by Arjun on 03/07/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        VStack(spacing: 20) {
            header
            capturePreview
            actionBar
        }
        .frame(minWidth: 720, minHeight: 520)
        .padding(24)
        .alert(
            "Screen Capture",
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.alertMessage = nil
                    }
                }
            )
        ) {
            Button("Open Settings") {
                viewModel.openScreenRecordingSettings()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)

            Text("ClearshotX")
                .font(.largeTitle.weight(.semibold))

            Text("Capture the full main display and preview the result.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var capturePreview: some View {
        if let capture = viewModel.latestCapture {
            VStack(alignment: .leading, spacing: 10) {
                Image(nsImage: capture.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(capture.pixelWidth) x \(capture.pixelHeight) px")
                        .font(.caption.weight(.medium))

                    Text(capture.fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } else {
            ContentUnavailableView(
                "No Capture Yet",
                systemImage: "macwindow",
                description: Text("Take a full-screen capture to see the preview here.")
            )
            .frame(maxWidth: .infinity, maxHeight: 320)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.captureFullScreen()
            } label: {
                Label(
                    viewModel.isCapturing ? "Capturing..." : "Capture Full Screen",
                    systemImage: "camera.viewfinder"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCapturing)

            Button {
                viewModel.copyLatestCaptureToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(!viewModel.hasCapture)

            Spacer()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
