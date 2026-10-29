import Foundation
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin

public struct FaceLivenessColorSequence {
    public struct Frame {
        public let currentColor: [Int]
        public let previousColor: [Int]
        public let durationMilliseconds: Double
        public let shouldScroll: Bool
    }

    public let sequenceID: UUID
    public let frames: [Frame]
    public let nativeDispatchedAt: UInt64
}

/// Preloads host-rendered colors. The upstream Freshness implementation still
/// owns playback timing, color events, and the completion that finalizes video.
@MainActor
public final class FaceLivenessColorRenderer {
    public var onSequencePrepared: ((FaceLivenessColorSequence) -> Void)?
    public var onStarted: ((UUID, UInt64) -> Void)?
    public var onCompleted: ((UUID, UInt64) -> Void)?
    public var onCancelled: ((UUID) -> Void)?

    private var activeSequenceID: UUID?
    private var pendingStart: (() -> Void)?

    public init() {}

    public func acknowledgeReady(sequenceID: UUID) {
        guard activeSequenceID == sequenceID, let start = pendingStart else { return }
        pendingStart = nil
        onStarted?(sequenceID, Date().timestampMilliseconds)
        guard activeSequenceID == sequenceID else { return }
        start()
    }

    public func cancel() {
        let sequenceID = activeSequenceID
        activeSequenceID = nil
        pendingStart = nil
        if let sequenceID { onCancelled?(sequenceID) }
    }

    func prepare(
        _ colors: [FaceLivenessSession.DisplayColor],
        start: @escaping (UUID) -> Void
    ) {
        cancel()
        let sequenceID = UUID()
        activeSequenceID = sequenceID
        pendingStart = { start(sequenceID) }
        onSequencePrepared?(
            FaceLivenessColorSequence(
                sequenceID: sequenceID,
                frames: colors.enumerated().map { index, color in
                    .init(
                        currentColor: color.rgb._values,
                        previousColor: colors[max(0, index - 1)].rgb._values,
                        durationMilliseconds: color.duration,
                        shouldScroll: color.shouldScroll
                    )
                },
                nativeDispatchedAt: Date().timestampMilliseconds
            )
        )
    }

    func complete(sequenceID: UUID) {
        guard activeSequenceID == sequenceID else { return }
        activeSequenceID = nil
        pendingStart = nil
        onCompleted?(sequenceID, Date().timestampMilliseconds)
    }
}
