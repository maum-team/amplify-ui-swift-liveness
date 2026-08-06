//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#if DEBUG
import SwiftUI
import AVFoundation

/// No-op detector so previews don't need to load the CoreML model.
final class PreviewFaceDetector: FaceDetector {
    func detectFaces(from buffer: CVPixelBuffer) {}
    func setResultHandler(detectionResultHandler: FaceDetectionResultHandler) {}
}

extension FaceLivenessDetectionViewModel {
    /// A view model wired with stub dependencies, for Xcode previews only.
    static func preview(
        state: LivenessStateMachine.State = .initial
    ) -> FaceLivenessDetectionViewModel {
        FaceLivenessDetectionViewModel(
            faceDetector: PreviewFaceDetector(),
            faceInOvalMatching: FaceInOvalMatching(instructor: Instructor()),
            videoChunker: VideoChunker(
                assetWriter: LivenessAVAssetWriter(),
                assetWriterDelegate: VideoChunker.AssetWriterDelegate(),
                assetWriterInput: LivenessAVAssetWriterInput()
            ),
            stateMachine: .init(state: state),
            closeButtonAction: {},
            sessionID: UUID().uuidString,
            isPreviewScreenEnabled: false,
            challengeOptions: ChallengeOptions()
        )
    }
}

/// Lays out a real `OvalView` at roughly the proportions the service returns,
/// so previews render the production drawing code rather than a mock shape.
private final class OvalPreviewContainer: UIView {
    var style: OvalView.Style = .default {
        didSet { setNeedsLayout() }
    }

    private var ovalView: OvalView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        ovalView?.removeFromSuperview()

        let width = bounds.width * 0.78
        let height = width / 0.7
        let ovalFrame = CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )

        let view = OvalView(frame: bounds, ovalFrame: ovalFrame, style: style)
        addSubview(view)
        ovalView = view
    }
}

struct PreviewOvalView: UIViewRepresentable {
    var style: OvalView.Style = .default

    func makeUIView(context: Context) -> UIView {
        OvalPreviewContainer()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? OvalPreviewContainer)?.style = style
    }
}

/// Stand-in for the camera feed: the simulator has no camera, so previews of
/// the liveness UI render this instead of `CameraView`.
struct PreviewCameraPlaceholder: View {
    var body: some View {
        ZStack {
            Color(white: 0.35)
            PreviewOvalView()
        }
        .aspectRatio(3/4, contentMode: .fit)
    }
}
#endif
