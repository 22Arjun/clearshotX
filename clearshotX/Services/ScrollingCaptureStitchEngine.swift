//
//  ScrollingCaptureStitchEngine.swift
//  clearshotX
//

import Accelerate
import CoreGraphics
import Foundation

nonisolated struct ScrollingCaptureStitchConfiguration: Equatable, Sendable {
    /// The broad search is intentionally small. It estimates only a one-dimensional
    /// translation; the native-height plane below recovers the exact physical row.
    var maximumCoarseWidth = 256
    var maximumCoarseHeight = 640
    var nativeRefinementWidth = 192
    var preferredCorrelationBandHeight = 180
    var nativeRefinementBandHeight = 320
    var nativeRefinementRadius = 8
    var maximumCorrelationBands = 5

    var minimumOverlapFraction = 0.28
    var maximumScrollFraction = 0.72
    var correlationThreshold: Float = 0.85
    var minimumPeakMargin: Float = 0.012
    var minimumBandTexture: Float = 0.000_35
    var zeroOffsetTolerance = 2
    var stationaryDifferenceThreshold: Float = 0.012

    /// Explicit insets are always honored. Automatic detection can increase them
    /// after a non-zero provisional alignment has been established.
    var contentInsets: ScrollingCaptureContentInsets = .zero
    var maximumStickyFraction = 0.25
}

nonisolated enum ScrollingCaptureStitchDisposition: Equatable, Sendable {
    case accept
    case retryWithSmallerScrollDelta
    case stationary
}

nonisolated struct ScrollingCaptureStitchMatch: Equatable, Sendable {
    let verticalOffset: Int
    let correlation: Float
    let peakMargin: Float
    let detectedContentInsets: ScrollingCaptureContentInsets
    let disposition: ScrollingCaptureStitchDisposition

    var isReliable: Bool {
        disposition != .retryWithSmallerScrollDelta
    }

    var isStationary: Bool {
        disposition == .stationary
    }
}

nonisolated enum ScrollingCaptureStitchError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidFrame
    case inconsistentFrameSize
    case insufficientOverlap
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "The scrolling stitch configuration is invalid."
        case .invalidFrame:
            "A scrolling stitch frame has no usable pixels."
        case .inconsistentFrameSize:
            "Scrolling stitch frames must have identical native dimensions."
        case .insufficientOverlap:
            "The frames do not leave enough searchable overlap."
        case .imageConversionFailed:
            "The scrolling stitch analysis plane could not be created."
        }
    }
}

/// Finds the vertical translation between two native viewport frames. Accelerate
/// computes normalized cross-correlation (NCC); Core Graphics is used only to make
/// bounded grayscale analysis planes. The caller retains and crops the untouched
/// input `CGImage` objects, so no output pixel is ever sourced from an analysis plane.
nonisolated final class ScrollingCaptureStitchEngine {
    let configuration: ScrollingCaptureStitchConfiguration

    init(configuration: ScrollingCaptureStitchConfiguration = .init()) {
        self.configuration = configuration
    }

    func match(
        previous: CGImage,
        current: CGImage
    ) throws -> ScrollingCaptureStitchMatch {
        try validate(previous: previous, current: current)

        guard let coarsePrevious = NCCPlane(
            image: previous,
            maximumWidth: configuration.maximumCoarseWidth,
            maximumHeight: configuration.maximumCoarseHeight
        ), let coarseCurrent = NCCPlane(
            image: current,
            maximumWidth: configuration.maximumCoarseWidth,
            maximumHeight: configuration.maximumCoarseHeight
        ) else {
            throw ScrollingCaptureStitchError.imageConversionFailed
        }

        let coarseInsets = scaledInsets(
            configuration.contentInsets,
            verticalScale: coarsePrevious.verticalScale
        )
        let coarseSearch = try search(
            previous: coarsePrevious,
            current: coarseCurrent,
            contentInsets: coarseInsets,
            preferredBandHeight: max(
                24,
                Int((Double(configuration.preferredCorrelationBandHeight)
                    * coarsePrevious.verticalScale).rounded())
            ),
            offsets: nil
        )

        let proposedNativeOffset = Int(
            (Double(coarseSearch.best.offset) / max(coarsePrevious.verticalScale, 0.000_001))
                .rounded()
        )

        // Horizontal reduction is safe for registration, but every vertical row is
        // preserved here. This pass makes the returned offset exact on Retina and
        // on viewports taller than the broad analysis plane.
        guard let nativePrevious = NCCPlane(
            image: previous,
            maximumWidth: configuration.nativeRefinementWidth,
            maximumHeight: previous.height
        ), let nativeCurrent = NCCPlane(
            image: current,
            maximumWidth: configuration.nativeRefinementWidth,
            maximumHeight: current.height
        ) else {
            throw ScrollingCaptureStitchError.imageConversionFailed
        }

        let explicitInsets = configuration.contentInsets
        var nativeSearch = try refinedSearch(
            previous: nativePrevious,
            current: nativeCurrent,
            around: proposedNativeOffset,
            contentInsets: explicitInsets
        )

        var detectedInsets = explicitInsets
        if nativeSearch.best.offset > configuration.zeroOffsetTolerance {
            let automaticInsets = detectFixedContentInsets(
                previous: nativePrevious,
                current: nativeCurrent,
                offset: nativeSearch.best.offset
            )
            detectedInsets = ScrollingCaptureContentInsets(
                top: max(explicitInsets.top, automaticInsets.top),
                bottom: max(explicitInsets.bottom, automaticInsets.bottom)
            )
            if detectedInsets != explicitInsets {
                nativeSearch = try refinedSearch(
                    previous: nativePrevious,
                    current: nativeCurrent,
                    around: nativeSearch.best.offset,
                    contentInsets: detectedInsets
                )
            }
        }

        let zeroDifference = meanAbsoluteDifference(
            previous: nativePrevious,
            current: nativeCurrent,
            offset: 0,
            contentInsets: detectedInsets
        )
        let isStationary = nativeSearch.best.offset <= configuration.zeroOffsetTolerance
            && zeroDifference <= configuration.stationaryDifferenceThreshold

        let nativeMargin = peakMargin(in: nativeSearch)
        let coarseMargin = peakMargin(in: coarseSearch)
        let margin = min(nativeMargin, coarseMargin)
        let hasReliablePeak = nativeSearch.best.correlation
                >= configuration.correlationThreshold
            && margin >= configuration.minimumPeakMargin

        let disposition: ScrollingCaptureStitchDisposition
        if isStationary {
            disposition = .stationary
        } else if hasReliablePeak {
            disposition = .accept
        } else {
            disposition = .retryWithSmallerScrollDelta
        }

        return ScrollingCaptureStitchMatch(
            verticalOffset: nativeSearch.best.offset,
            correlation: nativeSearch.best.correlation,
            peakMargin: margin,
            detectedContentInsets: detectedInsets,
            disposition: disposition
        )
    }

    private func validate(previous: CGImage, current: CGImage) throws {
        guard configuration.maximumCoarseWidth > 0,
              configuration.maximumCoarseHeight > 0,
              configuration.nativeRefinementWidth > 0,
              configuration.preferredCorrelationBandHeight > 0,
              configuration.nativeRefinementBandHeight > 0,
              configuration.nativeRefinementRadius >= 0,
              configuration.maximumCorrelationBands > 0,
              configuration.minimumBandTexture >= 0,
              configuration.minimumOverlapFraction > 0,
              configuration.minimumOverlapFraction < 1,
              configuration.maximumScrollFraction > 0,
              configuration.maximumScrollFraction < 1,
              configuration.maximumScrollFraction
                <= 1 - configuration.minimumOverlapFraction,
              configuration.correlationThreshold >= -1,
              configuration.correlationThreshold <= 1,
              configuration.minimumPeakMargin >= 0,
              configuration.maximumStickyFraction >= 0,
              configuration.maximumStickyFraction < 0.5
        else {
            throw ScrollingCaptureStitchError.invalidConfiguration
        }
        guard previous.width > 0, previous.height > 0,
              current.width > 0, current.height > 0 else {
            throw ScrollingCaptureStitchError.invalidFrame
        }
        guard previous.width == current.width,
              previous.height == current.height else {
            throw ScrollingCaptureStitchError.inconsistentFrameSize
        }
        let insets = configuration.contentInsets
        guard insets.top + insets.bottom < previous.height else {
            throw ScrollingCaptureStitchError.invalidConfiguration
        }
    }

    private struct Candidate {
        let offset: Int
        let correlation: Float
    }

    private struct SearchResult {
        let best: Candidate
        let candidates: [Candidate]
    }

    private func refinedSearch(
        previous: NCCPlane,
        current: NCCPlane,
        around proposedOffset: Int,
        contentInsets: ScrollingCaptureContentInsets
    ) throws -> SearchResult {
        let contentHeight = previous.height - contentInsets.top - contentInsets.bottom
        guard contentHeight > 2 else {
            throw ScrollingCaptureStitchError.insufficientOverlap
        }
        let maximumOffset = maximumOffset(for: contentHeight)
        let lower = max(0, proposedOffset - configuration.nativeRefinementRadius)
        let upper = min(maximumOffset, proposedOffset + configuration.nativeRefinementRadius)
        guard lower <= upper else {
            throw ScrollingCaptureStitchError.insufficientOverlap
        }
        return try search(
            previous: previous,
            current: current,
            contentInsets: contentInsets,
            preferredBandHeight: configuration.nativeRefinementBandHeight,
            offsets: lower...upper
        )
    }

    private func search(
        previous: NCCPlane,
        current: NCCPlane,
        contentInsets: ScrollingCaptureContentInsets,
        preferredBandHeight: Int,
        offsets requestedOffsets: ClosedRange<Int>?
    ) throws -> SearchResult {
        guard previous.width == current.width,
              previous.height == current.height else {
            throw ScrollingCaptureStitchError.inconsistentFrameSize
        }
        let contentTop = min(previous.height, contentInsets.top)
        let contentBottom = max(contentTop, previous.height - contentInsets.bottom)
        let contentHeight = contentBottom - contentTop
        let maximumOffset = maximumOffset(for: contentHeight)
        guard maximumOffset >= 0 else {
            throw ScrollingCaptureStitchError.insufficientOverlap
        }
        let offsets = requestedOffsets ?? 0...maximumOffset
        guard offsets.lowerBound >= 0,
              offsets.upperBound <= maximumOffset else {
            throw ScrollingCaptureStitchError.insufficientOverlap
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(offsets.count)
        for offset in offsets {
            let overlapHeight = contentHeight - offset
            guard overlapHeight > 1 else { continue }
            let bandHeight = min(preferredBandHeight, overlapHeight)
            let correlation = multiBandCorrelation(
                previous: previous,
                current: current,
                contentTop: contentTop,
                offset: offset,
                overlapHeight: overlapHeight,
                bandHeight: bandHeight
            )
            candidates.append(Candidate(offset: offset, correlation: correlation))
        }
        guard let best = candidates.max(by: {
            if $0.correlation == $1.correlation { return $0.offset > $1.offset }
            return $0.correlation < $1.correlation
        }) else {
            throw ScrollingCaptureStitchError.insufficientOverlap
        }
        return SearchResult(best: best, candidates: candidates)
    }

    private func maximumOffset(for contentHeight: Int) -> Int {
        let overlapLimited = contentHeight - max(
            2,
            Int((Double(contentHeight) * configuration.minimumOverlapFraction).rounded(.up))
        )
        let fractionLimited = Int(
            (Double(contentHeight) * configuration.maximumScrollFraction).rounded(.down)
        )
        return min(overlapLimited, fractionLimited)
    }

    private func peakMargin(in result: SearchResult) -> Float {
        let exclusionRadius = max(2, configuration.zeroOffsetTolerance + 1)
        let second = result.candidates
            .filter { abs($0.offset - result.best.offset) > exclusionRadius }
            .map(\.correlation)
            .max() ?? -1
        return max(0, result.best.correlation - second)
    }

    private struct CorrelationSample {
        let correlation: Float
        let texture: Float
    }

    private func multiBandCorrelation(
        previous: NCCPlane,
        current: NCCPlane,
        contentTop: Int,
        offset: Int,
        overlapHeight: Int,
        bandHeight: Int
    ) -> Float {
        let starts = bandStarts(overlapHeight: overlapHeight, bandHeight: bandHeight)
        var weightedCorrelation: Float = 0
        var totalWeight: Float = 0
        var fallbackCorrelation: Float = -1

        for localTop in starts {
            let bandTop = contentTop + localTop
            let currentStart = bandTop * previous.width
            let previousStart = (bandTop + offset) * previous.width
            let sampleCount = bandHeight * previous.width
            let sample = normalizedCrossCorrelation(
                previous: previous.pixels,
                previousStart: previousStart,
                current: current.pixels,
                currentStart: currentStart,
                count: sampleCount
            )
            fallbackCorrelation = max(fallbackCorrelation, sample.correlation)
            guard sample.texture >= configuration.minimumBandTexture else { continue }
            let weight = max(sample.texture, configuration.minimumBandTexture)
            weightedCorrelation += sample.correlation * weight
            totalWeight += weight
        }

        if totalWeight > 0 {
            return weightedCorrelation / totalWeight
        }
        return fallbackCorrelation
    }

    private func bandStarts(overlapHeight: Int, bandHeight: Int) -> [Int] {
        guard overlapHeight > bandHeight else { return [0] }
        let available = overlapHeight - bandHeight
        let count = min(
            configuration.maximumCorrelationBands,
            max(1, available / max(1, bandHeight / 2) + 1)
        )
        guard count > 1 else { return [available / 2] }
        return (0..<count).map { index in
            Int((Double(available) * Double(index) / Double(count - 1)).rounded())
        }
    }

    private func normalizedCrossCorrelation(
        previous: [Float],
        previousStart: Int,
        current: [Float],
        currentStart: Int,
        count: Int
    ) -> CorrelationSample {
        guard count > 1,
              previousStart >= 0,
              currentStart >= 0,
              previousStart + count <= previous.count,
              currentStart + count <= current.count else {
            return CorrelationSample(correlation: -1, texture: 0)
        }

        var sumPrevious: Float = 0
        var sumCurrent: Float = 0
        var squarePrevious: Float = 0
        var squareCurrent: Float = 0
        var dot: Float = 0
        let length = vDSP_Length(count)
        previous.withUnsafeBufferPointer { previousBuffer in
            current.withUnsafeBufferPointer { currentBuffer in
                guard let previousBase = previousBuffer.baseAddress,
                      let currentBase = currentBuffer.baseAddress else { return }
                let lhs = previousBase.advanced(by: previousStart)
                let rhs = currentBase.advanced(by: currentStart)
                vDSP_sve(lhs, 1, &sumPrevious, length)
                vDSP_sve(rhs, 1, &sumCurrent, length)
                vDSP_svesq(lhs, 1, &squarePrevious, length)
                vDSP_svesq(rhs, 1, &squareCurrent, length)
                vDSP_dotpr(lhs, 1, rhs, 1, &dot, length)
            }
        }

        let sampleCount = Float(count)
        let covariance = dot - (sumPrevious * sumCurrent / sampleCount)
        let variancePrevious = max(
            0,
            squarePrevious - (sumPrevious * sumPrevious / sampleCount)
        )
        let varianceCurrent = max(
            0,
            squareCurrent - (sumCurrent * sumCurrent / sampleCount)
        )
        let denominator = sqrt(variancePrevious * varianceCurrent)
        let texture = denominator / (sampleCount * 255.0 * 255.0)
        guard denominator > 0.000_1 else {
            let meanDelta = abs(sumPrevious - sumCurrent) / sampleCount
            return CorrelationSample(
                correlation: meanDelta <= 0.5 ? 1 : 0,
                texture: 0
            )
        }
        return CorrelationSample(
            correlation: min(1, max(-1, covariance / denominator)),
            texture: texture
        )
    }

    private func scaledInsets(
        _ insets: ScrollingCaptureContentInsets,
        verticalScale: Double
    ) -> ScrollingCaptureContentInsets {
        ScrollingCaptureContentInsets(
            top: Int((Double(insets.top) * verticalScale).rounded()),
            bottom: Int((Double(insets.bottom) * verticalScale).rounded())
        )
    }

    private func meanAbsoluteDifference(
        previous: NCCPlane,
        current: NCCPlane,
        offset: Int,
        contentInsets: ScrollingCaptureContentInsets
    ) -> Float {
        let top = min(previous.height, contentInsets.top)
        let bottom = max(top, previous.height - contentInsets.bottom)
        let rowCount = bottom - top - offset
        guard rowCount > 0 else { return 1 }
        let rowStride = max(1, rowCount / 240)
        let columnStride = max(1, previous.width / 96)
        var total: Float = 0
        var samples = 0
        var row = 0
        while row < rowCount {
            let previousBase = (top + row + offset) * previous.width
            let currentBase = (top + row) * current.width
            var column = 0
            while column < previous.width {
                total += abs(
                    previous.pixels[previousBase + column]
                        - current.pixels[currentBase + column]
                )
                samples += 1
                column += columnStride
            }
            row += rowStride
        }
        return samples > 0 ? total / Float(samples * 255) : 1
    }

    /// Detect only fixed bands attached to viewport boundaries. Evidence rows must
    /// agree at zero displacement and disagree with the document-motion hypothesis.
    /// Small neutral padding gaps are bridged so padded browser navigation is still
    /// classified as one sticky band.
    private func detectFixedContentInsets(
        previous: NCCPlane,
        current: NCCPlane,
        offset: Int
    ) -> ScrollingCaptureContentInsets {
        guard offset > configuration.zeroOffsetTolerance else { return .zero }
        let maximumBand = min(
            Int((Double(previous.height) * configuration.maximumStickyFraction).rounded()),
            previous.height - 2
        )
        guard maximumBand >= 4 else { return .zero }

        let stableThreshold: Float = 0.018
        let separation: Float = 0.035
        let maximumPaddingGap = max(8, min(24, previous.height / 24))
        let maximumLeadingPadding = max(8, min(32, previous.height / 32))

        var topFirst = -1
        var topLast = -1
        var topEvidence = 0
        var topGap = 0
        for row in 0..<maximumBand {
            let zero = rowDifference(
                previous: previous,
                previousRow: row,
                current: current,
                currentRow: row
            )
            let shiftedRow = row + offset
            let shifted = shiftedRow < previous.height
                ? rowDifference(
                    previous: previous,
                    previousRow: shiftedRow,
                    current: current,
                    currentRow: row
                )
                : 1
            if zero <= stableThreshold, shifted >= zero + separation {
                if topFirst < 0 { topFirst = row }
                topLast = row
                topEvidence += 1
                topGap = 0
            } else if topFirst >= 0 {
                topGap += 1
                if topGap > maximumPaddingGap { break }
            }
        }

        var bottomFirst = previous.height
        var bottomLast = previous.height
        var bottomEvidence = 0
        var bottomGap = 0
        let bottomLimit = max(0, previous.height - maximumBand)
        for row in stride(from: previous.height - 1, through: bottomLimit, by: -1) {
            let zero = rowDifference(
                previous: previous,
                previousRow: row,
                current: current,
                currentRow: row
            )
            let shiftedRow = row - offset
            let shifted = shiftedRow >= 0
                ? rowDifference(
                    previous: previous,
                    previousRow: shiftedRow,
                    current: current,
                    currentRow: row
                )
                : 1
            if zero <= stableThreshold, shifted >= zero + separation {
                if bottomLast == previous.height { bottomLast = row }
                bottomFirst = row
                bottomEvidence += 1
                bottomGap = 0
            } else if bottomLast < previous.height {
                bottomGap += 1
                if bottomGap > maximumPaddingGap { break }
            }
        }

        let hasTop = topEvidence >= 4 && topFirst <= maximumLeadingPadding
        let hasBottom = bottomEvidence >= 4
            && previous.height - 1 - bottomLast <= maximumLeadingPadding
        let top = hasTop ? topLast + 1 : 0
        let bottom = hasBottom ? previous.height - bottomFirst : 0
        guard top + bottom < previous.height / 2 else { return .zero }
        return ScrollingCaptureContentInsets(top: top, bottom: bottom)
    }

    private func rowDifference(
        previous: NCCPlane,
        previousRow: Int,
        current: NCCPlane,
        currentRow: Int
    ) -> Float {
        guard previousRow >= 0, previousRow < previous.height,
              currentRow >= 0, currentRow < current.height else { return 1 }
        let edgeInset = min(max(1, previous.width / 32), previous.width / 4)
        let end = max(edgeInset + 1, previous.width - edgeInset)
        let previousBase = previousRow * previous.width
        let currentBase = currentRow * current.width
        var total: Float = 0
        for column in edgeInset..<end {
            total += abs(
                previous.pixels[previousBase + column]
                    - current.pixels[currentBase + column]
            )
        }
        return total / Float(max(1, end - edgeInset) * 255)
    }
}

private nonisolated struct NCCPlane {
    let width: Int
    let height: Int
    let verticalScale: Double
    let pixels: [Float]

    init?(image: CGImage, maximumWidth: Int, maximumHeight: Int) {
        guard image.width > 0, image.height > 0,
              maximumWidth > 0, maximumHeight > 0 else { return nil }
        let width = min(image.width, maximumWidth)
        let height = min(image.height, maximumHeight)
        var bytes = [UInt8](repeating: 0, count: width * height)
        let didDraw = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let baseAddress = storage.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var floats = [Float](repeating: 0, count: bytes.count)
        bytes.withUnsafeBufferPointer { source in
            floats.withUnsafeMutableBufferPointer { destination in
                guard let sourceBase = source.baseAddress,
                      let destinationBase = destination.baseAddress else { return }
                vDSP_vfltu8(
                    sourceBase,
                    1,
                    destinationBase,
                    1,
                    vDSP_Length(bytes.count)
                )
            }
        }
        self.width = width
        self.height = height
        verticalScale = Double(height) / Double(image.height)
        pixels = floats
    }
}
