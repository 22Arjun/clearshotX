//
//  EditorBackgroundInspectorView.swift
//  clearshotX
//

import AppKit
import SwiftUI

struct EditorBackgroundInspectorView: View {
    @ObservedObject var viewModel: EditorViewModel

    private let swatchColumns = [
        GridItem(.adaptive(minimum: 52, maximum: 72), spacing: 8),
    ]
    private let alignmentColumns = Array(
        repeating: GridItem(.fixed(30), spacing: 5),
        count: 3
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    backgroundSection

                    if viewModel.backgroundComposition.isEnabled {
                        canvasSection
                        layoutSection
                        appearanceSection
                        outputSection
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 292)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("Background")
                    .font(.system(size: 14, weight: .semibold))

                Text("Non-destructive composition")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.resetBackgroundComposition()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Reset Background")
            .disabled(viewModel.backgroundComposition == .default)
            .accessibilityLabel("Reset Background")

            Button {
                viewModel.perform(.background)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close Background Inspector")
            .accessibilityLabel("Close Background Inspector")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var backgroundSection: some View {
        inspectorSection("Background") {
            Button {
                viewModel.setBackgroundPaint(.none)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: viewModel.backgroundComposition.paint == .none ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.backgroundComposition.paint == .none ? Color.accentColor : Color.secondary)
                    Text("None")
                    Spacer()
                }
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(inspectorControlBackground)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Gradients")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: swatchColumns, spacing: 8) {
                ForEach(EditorBackgroundGradient.allCases) { gradient in
                    gradientSwatch(gradient)
                }
            }

            Text("Plain colors")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: 8) {
                ForEach(EditorBackgroundSolidColor.allCases) { solidColor in
                    solidColorSwatch(solidColor)
                }
            }
        }
    }

    private var canvasSection: some View {
        inspectorSection("Canvas") {
            Picker(
                "Aspect ratio",
                selection: Binding(
                    get: { viewModel.backgroundComposition.canvas },
                    set: { viewModel.setBackgroundCanvas($0) }
                )
            ) {
                ForEach(EditorBackgroundCanvas.allCases) { canvas in
                    Text(canvas.title).tag(canvas)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Canvas Aspect Ratio")
        }
    }

    private var layoutSection: some View {
        inspectorSection("Layout") {
            labeledSlider(
                title: "Padding",
                value: Binding(
                    get: { viewModel.backgroundComposition.padding },
                    set: { viewModel.setBackgroundPadding($0) }
                ),
                range: 0...240,
                suffix: "px"
            )

            HStack(alignment: .top) {
                Text("Alignment")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                LazyVGrid(columns: alignmentColumns, spacing: 5) {
                    ForEach(EditorBackgroundAlignment.allCases) { alignment in
                        alignmentButton(alignment)
                    }
                }
                .frame(width: 100)
            }
        }
    }

    private var appearanceSection: some View {
        inspectorSection("Appearance") {
            labeledSlider(
                title: "Corners",
                value: Binding(
                    get: { viewModel.backgroundComposition.cornerRadius },
                    set: { viewModel.setBackgroundCornerRadius($0) }
                ),
                range: 0...64,
                suffix: "px"
            )

            Toggle(
                "Shadow",
                isOn: Binding(
                    get: { viewModel.backgroundComposition.shadow.isEnabled },
                    set: { viewModel.setBackgroundShadowEnabled($0) }
                )
            )
            .font(.system(size: 11.5, weight: .medium))

            if viewModel.backgroundComposition.shadow.isEnabled {
                labeledSlider(
                    title: "Shadow strength",
                    value: Binding(
                        get: { viewModel.backgroundComposition.shadow.opacity },
                        set: { viewModel.setBackgroundShadowOpacity($0) }
                    ),
                    range: 0.05...0.6,
                    suffix: "%",
                    displayMultiplier: 100
                )
            }
        }
    }

    private var outputSection: some View {
        inspectorSection("Output") {
            HStack {
                Text("Dimensions")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.backgroundOutputSizeTitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .tracking(0.7)

            content()
        }
    }

    private func gradientSwatch(_ gradient: EditorBackgroundGradient) -> some View {
        let isSelected = viewModel.backgroundComposition.paint == .gradient(gradient)

        return Button {
            viewModel.setBackgroundPaint(.gradient(gradient))
        } label: {
            LinearGradient(
                colors: gradient.colors.map { Color(nsColor: $0.nsColor) },
                startPoint: UnitPoint(x: gradient.startPoint.x, y: gradient.startPoint.y),
                endPoint: UnitPoint(x: gradient.endPoint.x, y: gradient.endPoint.y)
            )
            .frame(height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.22), lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .help(gradient.title)
        .accessibilityLabel("\(gradient.title) Gradient")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func solidColorSwatch(_ solidColor: EditorBackgroundSolidColor) -> some View {
        let isSelected = viewModel.backgroundComposition.paint == .solid(solidColor)

        return Button {
            viewModel.setBackgroundPaint(.solid(solidColor))
        } label: {
            Circle()
                .fill(Color(nsColor: solidColor.color.nsColor))
                .frame(width: 25, height: 25)
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 3 : 1)
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(solidColor == .cloud ? Color.black : Color.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(solidColor.title)
        .accessibilityLabel(solidColor.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func alignmentButton(_ alignment: EditorBackgroundAlignment) -> some View {
        let isSelected = viewModel.backgroundComposition.alignment == alignment

        return Button {
            viewModel.setBackgroundAlignment(alignment)
        } label: {
            Circle()
                .fill(isSelected ? Color.accentColor : Color(nsColor: .tertiaryLabelColor).opacity(0.42))
                .frame(width: isSelected ? 9 : 6, height: isSelected ? 9 : 6)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(alignment.accessibilityTitle)
        .accessibilityLabel(alignment.accessibilityTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func labeledSlider(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        suffix: String,
        displayMultiplier: CGFloat = 1
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 2) {
                    TextField(
                        "",
                        value: Binding(
                            get: { Double(value.wrappedValue * displayMultiplier) },
                            set: { value.wrappedValue = CGFloat($0) / displayMultiplier }
                        ),
                        format: .number.precision(.fractionLength(0))
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: 38)

                    Text(suffix)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .frame(height: 23)
                .background(inspectorControlBackground)
            }

            Slider(
                value: value,
                in: range,
                onEditingChanged: { isEditing in
                    if isEditing {
                        viewModel.beginBackgroundContinuousEditing()
                    } else {
                        viewModel.endBackgroundContinuousEditing()
                    }
                }
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var inspectorControlBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            }
    }
}
