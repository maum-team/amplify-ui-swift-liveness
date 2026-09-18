//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import SwiftUI

struct _FaceLivenessDetectionView<VideoView: View>: View {
    let videoView: VideoView
    let viewCustomization: FaceLivenessViewCustomization
    @ObservedObject var viewModel: FaceLivenessDetectionViewModel
    @Binding var displayResultsView: Bool

    init(
        viewModel: FaceLivenessDetectionViewModel,
        viewCustomization: FaceLivenessViewCustomization = .init(),
        @ViewBuilder videoView: @escaping () -> VideoView
    ) {
        self.viewModel = viewModel
        self.viewCustomization = viewCustomization
        self.videoView = videoView()

        self._displayResultsView = .init(
            get: { viewModel.livenessState.state == .completed },
            set: { _ in }
        )
    }

    @ViewBuilder
    var body: some View {
        if viewCustomization.externalFreshnessController != nil {
            externalContent
        } else {
            nativeContent
        }
    }

    private var externalContent: some View {
        ZStack {
            Color.black
            videoView
            if let presentation = viewModel.livenessState.shootingPresentation,
               let overlay = viewCustomization.shootingOverlay {
                overlay.makeView(FaceLivenessShootingContext(
                    instruction: viewModel.livenessState.shootingInstructionText,
                    progress: presentation.progress,
                    showsGuideOval: presentation.showsGuideOval,
                    onCancel: viewModel.closeButtonAction
                ))
            } else if viewModel.livenessState.isVerifying,
                      let overlay = viewCustomization.verificationOverlay {
                overlay.makeView(FaceLivenessVerificationContext(
                    instruction: LocalizedStrings.challenge_verifying,
                    onCancel: viewModel.closeButtonAction
                ))
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    // Kept identical to the upstream presentation when no external controller is supplied.
    private var nativeContent: some View {
        ZStack {
            Color.black
            ZStack {
                videoView
                VStack {
                    HStack(alignment: .top) {
                        if viewModel.livenessState.shouldDisplayRecordingIcon {
                            RecordingButton()
                                .accessibilityHidden(true)
                        }

                        Spacer()

                        CloseButton(
                            action: viewModel.closeButtonAction
                        )
                    }
                    .padding()

                    InstructionContainerView(
                        viewModel: viewModel
                    )

                    Spacer()
                }
                .padding([.leading, .trailing])
                .aspectRatio(3/4, contentMode: .fit)
                .frame(maxWidth: .infinity)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

private extension LivenessStateMachine {
    var shootingPresentation: (progress: Double, showsGuideOval: Bool)? {
        switch state {
        case .initial, .pendingFacePreparedConfirmation, .waitForRecording, .recording(ovalDisplayed: false):
            return (0, true)
        case .recording(ovalDisplayed: true):
            return (0.2, false)
        case .awaitingFaceInOvalMatch(_, let percentage):
            return (percentage, false)
        default:
            return nil
        }
    }

    var shootingInstructionText: String {
        switch state {
        case .pendingFacePreparedConfirmation(let reason):
            return reason.localizedValue
        case .awaitingFaceInOvalMatch(.faceTooClose, _):
            return LocalizedStrings.challenge_instruction_move_face_back
        case .awaitingFaceInOvalMatch(let reason, _):
            return reason.localizedValue
        default:
            return LocalizedStrings.challenge_instruction_move_face_closer
        }
    }

    var isVerifying: Bool {
        switch state {
        case .completedDisplayingFreshness, .completedNoLightCheck:
            return true
        default:
            return false
        }
    }
}
