//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public struct FaceLivenessUIState: Equatable {
    public let phase: String
    public let instruction: String
    public let progress: Double
    public let isRecording: Bool
}

public struct FaceLivenessPresentationOval: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Observes presentation data for a host-rendered overlay. Matching, camera capture,
/// playback timing and service events remain owned by FaceLiveness.
@MainActor
public final class FaceLivenessPresentationController {
    public let colorRenderer: FaceLivenessColorRenderer?
    public var onStateChanged: ((FaceLivenessUIState) -> Void)?
    public var onOvalChanged: ((FaceLivenessPresentationOval) -> Void)?

    private var lastState: FaceLivenessUIState?
    private var lastOval: FaceLivenessPresentationOval?

    public init(colorRenderer: FaceLivenessColorRenderer? = nil) {
        self.colorRenderer = colorRenderer
    }

    func publish(_ stateMachine: LivenessStateMachine) {
        guard let state = presentation(for: stateMachine), state != lastState else { return }
        lastState = state
        onStateChanged?(state)
    }

    func publishOval(frame: CGRect, viewport: CGRect) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let oval = FaceLivenessPresentationOval(
            x: (frame.minX - viewport.minX) / viewport.width,
            y: (frame.minY - viewport.minY) / viewport.height,
            width: frame.width / viewport.width,
            height: frame.height / viewport.height
        )
        guard oval != lastOval else { return }
        lastOval = oval
        onOvalChanged?(oval)
    }

    private func presentation(for stateMachine: LivenessStateMachine) -> FaceLivenessUIState? {
        let phase: String
        let instruction: String
        let progress: Double

        switch stateMachine.state {
        case .completedDisplayingFreshness, .completedNoLightCheck:
            phase = "verifying"
            instruction = LocalizedStrings.challenge_verifying
            progress = 1
        case .displayingFreshness:
            phase = "freshness"
            instruction = LocalizedStrings.challenge_instruction_hold_still
            progress = 1
        case .faceMatched:
            phase = "positioning"
            instruction = LocalizedStrings.challenge_instruction_hold_still
            progress = 1
        case .awaitingFaceInOvalMatch(let reason, let percentage):
            phase = "positioning"
            instruction = reason == .faceTooClose
                ? LocalizedStrings.challenge_instruction_move_face_back
                : reason.localizedValue
            progress = percentage
        case .pendingFacePreparedConfirmation(let reason):
            phase = "positioning"
            instruction = reason.localizedValue
            progress = 0
        case .recording(ovalDisplayed: true):
            phase = "positioning"
            instruction = LocalizedStrings.challenge_instruction_move_face_closer
            progress = 0.2
        case .initial, .awaitingChallengeType, .waitForRecording,
                .recording(ovalDisplayed: false):
            phase = "positioning"
            instruction = LocalizedStrings.amplify_ui_liveness_face_not_prepared_reason_pendingCheck
            progress = 0
        default:
            return nil
        }

        return FaceLivenessUIState(
            phase: phase,
            instruction: instruction,
            progress: progress,
            isRecording: stateMachine.shouldDisplayRecordingIcon
        )
    }
}
