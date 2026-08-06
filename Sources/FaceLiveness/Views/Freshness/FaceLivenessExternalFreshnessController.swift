//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin

/// A color transition emitted by the AWS freshness challenge.
///
/// This contains presentation metadata only. It intentionally excludes the
/// session identifier, camera frames, face geometry, and credentials.
public struct FaceLivenessFreshnessColorEvent {
    public let sequenceNumber: Int
    public let currentColor: [Int]
    public let previousColor: [Int]
    public let durationMilliseconds: Double
    public let shouldScroll: Bool
    public let nativeDispatchedAt: UInt64
}

public struct FaceLivenessExternalUiStateEvent {
    public let phase: String
    public let instruction: String
    public let progress: Double
}

public struct FaceLivenessExternalOvalEvent {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Optional local matching target for hosts that render their own oval.
///
/// The size is expressed against a reference viewport and scales uniformly
/// for the current viewport. AWS challenge metadata and server-side liveness
/// scoring are not modified.
public struct FaceLivenessExternalMatchingOvalConfiguration {
    public let width: Double
    public let height: Double
    public let referenceViewportWidth: Double
    public let referenceViewportHeight: Double

    public init(
        width: Double,
        height: Double,
        referenceViewportWidth: Double,
        referenceViewportHeight: Double
    ) {
        self.width = width
        self.height = height
        self.referenceViewportWidth = referenceViewportWidth
        self.referenceViewportHeight = referenceViewportHeight
    }
}

/// Experimental bridge for hosts that render the freshness colors outside of
/// FaceLiveness. Face capture, challenge timing, and AWS event submission stay
/// native; only the visual color layer is delegated to the host.
@MainActor
public final class FaceLivenessExternalFreshnessController {
    public var onStarted: ((UInt64) -> Void)?
    public var onColorChanged: ((FaceLivenessFreshnessColorEvent) -> Void)?
    public var onCompleted: ((UInt64) -> Void)?
    public var onUiStateChanged: ((FaceLivenessExternalUiStateEvent) -> Void)?
    public var onOvalChanged: ((FaceLivenessExternalOvalEvent) -> Void)?
    public var rendersOvalExternally = false
    public var matchingOvalConfiguration: FaceLivenessExternalMatchingOvalConfiguration?
    /// Local client-side fit tolerance. `1` preserves the AWS challenge values.
    public var matchingToleranceMultiplier = 1.0

    private struct PendingColor {
        let event: Freshness.ColorEvent
        let onAcknowledged: (Freshness.ColorEvent) -> Void
    }

    private var pendingColors: [Int: PendingColor] = [:]
    private var playbackTask: Task<Void, Never>?

    public init() {}

    deinit {
        playbackTask?.cancel()
    }

    /// Drives the AWS-provided sequence with a monotonic task clock while the
    /// host renders each transition. This avoids running the native 10ms
    /// Auto Layout animation behind an external renderer.
    func play(
        _ colorSequences: [FaceLivenessSession.DisplayColor],
        onAcknowledged: @escaping (Freshness.ColorEvent) -> Void,
        onComplete: @escaping () -> Void
    ) {
        playbackTask?.cancel()
        start(at: Date().timestampMilliseconds)

        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for (sequenceNumber, currentColor) in colorSequences.enumerated() {
                guard !Task.isCancelled else { return }

                let previousColor = sequenceNumber > 0
                    ? colorSequences[sequenceNumber - 1]
                    : currentColor
                let event = Freshness.ColorEvent(
                    currentColor: currentColor,
                    previousColor: previousColor,
                    sequenceNumber: sequenceNumber,
                    colorStartTime: Date().timestampMilliseconds
                )

                publish(event, onAcknowledged: onAcknowledged)

                let durationNanoseconds = UInt64(
                    max(0, currentColor.duration) * 1_000_000
                )
                do {
                    try await Task.sleep(nanoseconds: durationNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            complete(at: Date().timestampMilliseconds)
            playbackTask = nil
            onComplete()
        }
    }

    public func cancelPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        pendingColors.removeAll()
    }

    public func publishUiState(
        phase: String,
        instruction: String,
        progress: Double
    ) {
        onUiStateChanged?(
            FaceLivenessExternalUiStateEvent(
                phase: phase,
                instruction: instruction,
                progress: progress
            )
        )
    }

    public func publishOval(frame: CGRect, viewport: CGRect) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        onOvalChanged?(
            FaceLivenessExternalOvalEvent(
                x: frame.minX / viewport.width,
                y: frame.minY / viewport.height,
                width: frame.width / viewport.width,
                height: frame.height / viewport.height
            )
        )
    }

    func start(at timestamp: UInt64) {
        pendingColors.removeAll()
        onStarted?(timestamp)
    }

    func publish(
        _ event: Freshness.ColorEvent,
        onAcknowledged: @escaping (Freshness.ColorEvent) -> Void
    ) {
        pendingColors[event.sequenceNumber] = PendingColor(
            event: event,
            onAcknowledged: onAcknowledged
        )
        onColorChanged?(
            FaceLivenessFreshnessColorEvent(
                sequenceNumber: event.sequenceNumber,
                currentColor: event.currentColor.rgb._values,
                previousColor: event.previousColor.rgb._values,
                durationMilliseconds: event.currentColor.duration,
                shouldScroll: event.currentColor.shouldScroll,
                nativeDispatchedAt: event.colorStartTime
            )
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.resolve(
                sequenceNumber: event.sequenceNumber,
                displayedAt: Date().timestampMilliseconds
            )
        }
    }

    /// Confirms when the externally rendered color reached the host UI.
    public func acknowledgeColorDisplayed(
        sequenceNumber: Int,
        displayedAt: UInt64
    ) {
        resolve(sequenceNumber: sequenceNumber, displayedAt: displayedAt)
    }

    func complete(at timestamp: UInt64) {
        for sequenceNumber in pendingColors.keys.sorted() {
            resolve(sequenceNumber: sequenceNumber, displayedAt: timestamp)
        }
        onCompleted?(timestamp)
    }

    private func resolve(sequenceNumber: Int, displayedAt: UInt64) {
        guard let pending = pendingColors.removeValue(forKey: sequenceNumber) else {
            return
        }

        pending.onAcknowledged(
            Freshness.ColorEvent(
                currentColor: pending.event.currentColor,
                previousColor: pending.event.previousColor,
                sequenceNumber: pending.event.sequenceNumber,
                colorStartTime: displayedAt
            )
        )
    }
}
