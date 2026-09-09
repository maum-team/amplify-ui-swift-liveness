//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin

/// A single color transition inside a preloaded freshness sequence.
public struct FaceLivenessFreshnessFrame {
    public let currentColor: [Int]
    public let previousColor: [Int]
    public let durationMilliseconds: Double
    public let shouldScroll: Bool
}

/// The whole AWS freshness sequence, handed to the host in one dispatch.
///
/// This contains presentation metadata only. It intentionally excludes the
/// session identifier, camera frames, face geometry, and credentials.
///
/// The host renders the colors on its own clock, so the challenge never pays a
/// bridge round trip per color transition.
public struct FaceLivenessFreshnessSequenceEvent {
    /// Identifies this attempt, including retries within the same liveness session.
    public let sequenceID: UUID
    public let frames: [FaceLivenessFreshnessFrame]
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
    public var onFreshnessSequencePrepared: ((FaceLivenessFreshnessSequenceEvent) -> Void)?
    public var onCompleted: ((UInt64) -> Void)?
    /// The host must stop its animation and discard pending readiness for this ID.
    public var onCancelled: ((UUID) -> Void)?
    public var onUiStateChanged: ((FaceLivenessExternalUiStateEvent) -> Void)?
    public var onOvalChanged: ((FaceLivenessExternalOvalEvent) -> Void)?
    public var rendersOvalExternally = false
    public var matchingOvalConfiguration: FaceLivenessExternalMatchingOvalConfiguration?
    /// Local client-side fit tolerance. `1` preserves the AWS challenge values.
    public var matchingToleranceMultiplier = 1.0

    private var pendingPlaybackStart: (() -> Void)?
    private var playbackTask: Task<Void, Never>?
    private var activeSequenceID: UUID?

    public init() {}

    deinit {
        playbackTask?.cancel()
    }

    /// Drives the AWS-provided sequence with a monotonic task clock while the
    /// host renders each transition. This avoids running the native 10ms
    /// Auto Layout animation behind an external renderer.
    ///
    /// The whole sequence reaches `onFreshnessSequencePrepared` in a single
    /// dispatch, and playback starts on one `acknowledgeFreshnessReady(sequenceID:)`.
    /// Every color transition after that stays on this side of the bridge.
    /// Without a subscriber there is nothing to wait for, so playback starts
    /// right away on the native clock.
    func play(
        _ colorSequences: [FaceLivenessSession.DisplayColor],
        onAcknowledged: @escaping (Freshness.ColorEvent) -> Void,
        onComplete: @escaping () -> Void
    ) {
        cancelPlayback()
        let sequenceID = UUID()
        activeSequenceID = sequenceID

        guard let onFreshnessSequencePrepared else {
            startPlayback(
                colorSequences,
                sequenceID: sequenceID,
                onAcknowledged: onAcknowledged,
                onComplete: onComplete
            )
            return
        }

        pendingPlaybackStart = { [weak self] in
            self?.startPlayback(
                colorSequences,
                sequenceID: sequenceID,
                onAcknowledged: onAcknowledged,
                onComplete: onComplete
            )
        }
        onFreshnessSequencePrepared(
            FaceLivenessFreshnessSequenceEvent(
                sequenceID: sequenceID,
                frames: colorSequences.enumerated().map { sequenceNumber, currentColor in
                    let previousColor = sequenceNumber > 0
                        ? colorSequences[sequenceNumber - 1]
                        : currentColor
                    return FaceLivenessFreshnessFrame(
                        currentColor: currentColor.rgb._values,
                        previousColor: previousColor.rgb._values,
                        durationMilliseconds: currentColor.duration,
                        shouldScroll: currentColor.shouldScroll
                    )
                },
                nativeDispatchedAt: Date().timestampMilliseconds
            )
        )
    }

    /// Legacy acknowledgement cannot distinguish a delayed response from a previous attempt.
    @available(*, deprecated, message: "Use acknowledgeFreshnessReady(sequenceID:) for retry-safe readiness")
    public func acknowledgeFreshnessReady() {
        guard let sequenceID = activeSequenceID else { return }
        acknowledgeFreshnessReady(sequenceID: sequenceID)
    }

    /// Starts playback once for the matching attempt; stale or repeated responses are ignored.
    public func acknowledgeFreshnessReady(sequenceID: UUID) {
        guard activeSequenceID == sequenceID else { return }
        let startPlayback = pendingPlaybackStart
        pendingPlaybackStart = nil
        startPlayback?()
    }

    private func startPlayback(
        _ colorSequences: [FaceLivenessSession.DisplayColor],
        sequenceID: UUID,
        onAcknowledged: @escaping (Freshness.ColorEvent) -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard activeSequenceID == sequenceID else { return }
        onStarted?(Date().timestampMilliseconds)
        // A synchronous host callback may cancel or replace this attempt.
        guard activeSequenceID == sequenceID else { return }

        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for (sequenceNumber, currentColor) in colorSequences.enumerated() {
                guard !Task.isCancelled, self.activeSequenceID == sequenceID else { return }

                let previousColor = sequenceNumber > 0
                    ? colorSequences[sequenceNumber - 1]
                    : currentColor
                onAcknowledged(
                    Freshness.ColorEvent(
                        currentColor: currentColor,
                        previousColor: previousColor,
                        sequenceNumber: sequenceNumber,
                        colorStartTime: Date().timestampMilliseconds
                    )
                )

                let durationNanoseconds = UInt64(
                    max(0, currentColor.duration) * 1_000_000
                )
                do {
                    try await Task.sleep(nanoseconds: durationNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled, self.activeSequenceID == sequenceID else { return }
            let completedAt = Date().timestampMilliseconds
            // Commit completion before notifying the host: its cleanup may call cancelPlayback().
            activeSequenceID = nil
            playbackTask = nil
            onComplete()
            onCompleted?(completedAt)
        }
    }

    public func cancelPlayback() {
        let cancelledSequenceID = activeSequenceID
        activeSequenceID = nil
        playbackTask?.cancel()
        playbackTask = nil
        pendingPlaybackStart = nil
        if let cancelledSequenceID {
            onCancelled?(cancelledSequenceID)
        }
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
}
