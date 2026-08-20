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

    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            cameraPreview

            if let shootingPresentation = viewModel.livenessState.shootingPresentation,
               let shootingOverlay = viewCustomization.shootingOverlay {
                let context = FaceLivenessShootingContext(
                    instruction: viewModel.livenessState.shootingInstructionText,
                    progress: shootingPresentation.progress,
                    showsGuideOval: shootingPresentation.showsGuideOval,
                    onCancel: viewModel.closeButtonAction
                )

                shootingOverlay.makeView(context)
            } else if let shootingProgress = viewModel.livenessState.shootingProgress {
                ShootingOverlay(
                    instruction: viewModel.livenessState.shootingInstructionText,
                    progress: shootingProgress,
                    closeAction: viewModel.closeButtonAction
                )
            } else if viewModel.livenessState.isDisplayingFreshness,
                      viewCustomization.externalFreshnessController != nil {
                Color.clear
                    .allowsHitTesting(false)
            } else if viewModel.livenessState.isDisplayingFreshness,
                      let freshnessOverlay = viewCustomization.freshnessOverlay {
                freshnessOverlay.makeView(
                    FaceLivenessFreshnessContext(
                        instruction: LocalizedStrings.challenge_instruction_hold_still,
                        onCancel: viewModel.closeButtonAction
                    )
                )
            } else if viewModel.livenessState.isVerifying {
                let context = FaceLivenessVerificationContext(
                    instruction: LocalizedStrings.challenge_verifying,
                    onCancel: viewModel.closeButtonAction
                )

                if let verificationOverlay = viewCustomization.verificationOverlay {
                    verificationOverlay.makeView(context)
                } else {
                    VerificationOverlay(closeAction: context.onCancel)
                }
            } else {
                LegacyLivenessOverlay(viewModel: viewModel)
                    .edgesIgnoringSafeArea(.all)
            }
        }
    }

    @ViewBuilder
    private var cameraPreview: some View {
        if viewCustomization.usesFullScreenCameraPreview {
            videoView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
        } else {
            videoView
                .edgesIgnoringSafeArea(.all)
        }
    }
}

private struct ShootingOverlay: View {
    let instruction: String
    let progress: Double
    let closeAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = ResponsiveOverlayMetrics(size: geometry.size)

            ZStack(alignment: .topTrailing) {
                VStack(spacing: metrics.guidanceSpacing) {
                    Text(instruction)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)

                    LivenessProgressBar(progress: progress)
                        .frame(height: 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.guidanceTopPadding)
                .allowsHitTesting(false)

                LivenessCloseButton(action: closeAction)
                    .padding(.trailing, metrics.closeTrailingPadding)
            }
        }
    }
}

private struct VerificationOverlay: View {
    let closeAction: () -> Void

    private let instruction = LocalizedStrings.challenge_verifying

    var body: some View {
        GeometryReader { geometry in
            let metrics = ResponsiveOverlayMetrics(size: geometry.size)

            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(false)

                Text(instruction)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.guidanceTopPadding)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .allowsHitTesting(false)

                VerificationAnimationView(size: metrics.faceScanSize)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )

                LivenessCloseButton(action: closeAction)
                    .opacity(0.4)
                    .padding(.trailing, metrics.closeTrailingPadding)
            }
        }
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: instruction
            )
        }
    }
}

private struct VerificationAnimationView: View {
    let size: CGFloat

    var body: some View {
        ProgressView()
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct LivenessProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))

                Capsule()
                    .fill(Color.hex("#7DB8FF"))
                    .frame(
                        width: max(
                            0,
                            min(progress, 1) * geometry.size.width
                        )
                    )
            }
        }
    }
}

private struct LivenessCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text(LocalizedStrings.close_button_a11y))
    }
}

private struct ResponsiveOverlayMetrics {
    let horizontalPadding: CGFloat
    let closeTrailingPadding: CGFloat
    let guidanceTopPadding: CGFloat
    let guidanceSpacing: CGFloat
    let faceScanSize: CGFloat

    init(size: CGSize) {
        let shortestSide = min(size.width, size.height)

        horizontalPadding = min(40, max(20, size.width * 0.08))
        closeTrailingPadding = min(16, max(8, size.width * 0.035))
        guidanceTopPadding = min(64, max(52, size.height * 0.07))
        guidanceSpacing = min(14, max(10, size.height * 0.016))
        faceScanSize = min(200, max(140, shortestSide * 0.46))
    }
}

private struct LegacyLivenessOverlay: View {
    @ObservedObject var viewModel: FaceLivenessDetectionViewModel

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                if viewModel.livenessState.shouldDisplayRecordingIcon {
                    RecordingButton()
                        .accessibilityHidden(true)
                }

                Spacer()

                CloseButton(action: viewModel.closeButtonAction)
            }
            .padding()

            InstructionContainerView(viewModel: viewModel)

            Spacer()
        }
        .padding([.leading, .trailing])
        .aspectRatio(3/4, contentMode: .fit)
        .frame(maxWidth: .infinity)
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

    var shootingProgress: Double? {
        switch state {
        case .recording(ovalDisplayed: true):
            return 0.2
        case .awaitingFaceInOvalMatch(_, let percentage):
            return percentage
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

    var isDisplayingFreshness: Bool {
        switch state {
        case .faceMatched, .displayingFreshness:
            return true
        default:
            return false
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

#if DEBUG
struct _FaceLivenessDetectionView_Previews: PreviewProvider {
    static func preview(
        _ state: LivenessStateMachine.State
    ) -> some View {
        _FaceLivenessDetectionView(
            viewModel: .preview(state: state),
            videoView: { PreviewCameraPlaceholder() }
        )
    }

    static var previews: some View {
        Group {
            preview(.pendingFacePreparedConfirmation(.pendingCheck))
                .previewDisplayName("Pending check")

            preview(.awaitingFaceInOvalMatch(.moveFaceCloser, 0.4))
                .previewDisplayName("Move closer")

            preview(.awaitingFaceInOvalMatch(.faceTooClose, 0.9))
                .previewDisplayName("Too close")

            preview(.completedDisplayingFreshness)
                .previewDisplayName("Verifying")
        }
    }
}
#endif
