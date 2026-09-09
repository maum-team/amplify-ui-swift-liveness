//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import UIKit
import AVFoundation
import Vision
import Amplify
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin
import SwiftUI

final class _LivenessViewController: UIViewController {
    let viewModel: FaceLivenessDetectionViewModel
    var previewLayer: CALayer?

    let faceShapeLayer = CAShapeLayer()
    var ovalExists = false
    var ovalRect: CGRect?
    var freshness = Freshness()
    let freshnessView = FreshnessView()
    var readyForOval = false

    init(
        viewModel: FaceLivenessDetectionViewModel
    ) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        viewModel.livenessViewControllerDelegate = self
        viewModel.normalizeFace = { [weak self] face in
            guard let self = self else { return face }
            return DispatchQueue.main.sync {
                face.normalize(width: self.view.frame.width, height: self.view.frame.width / 3 * 4)
            }
        }
    }
    
    deinit {
        guard let previewLayer = self.previewLayer else { return }
        previewLayer.removeFromSuperlayer()
        (previewLayer as? AVCaptureVideoPreviewLayer)?.session = nil
        self.previewLayer = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        layoutSubviews()
        setupAVLayer()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let previewLayer else { return }

        if viewModel.usesFullScreenCameraPreview {
            previewLayer.frame = view.bounds
        } else {
            previewLayer.position = view.center
        }
    }

    private func layoutSubviews() {
        freshnessView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(freshnessView)
        NSLayoutConstraint.activate([
            freshnessView.topAnchor.constraint(equalTo: view.topAnchor),
            freshnessView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            freshnessView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            freshnessView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        freshnessView.clearColors()
    }

    private func setupAVLayer() {
        guard previewLayer == nil else { return }
        let width = view.frame.width
        let height = width / 3 * 4
        let cameraFrame = viewModel.usesFullScreenCameraPreview
            ? view.bounds
            : CGRect(x: 0, y: 0, width: width, height: height)

        guard let avLayer = viewModel.configureCamera(withinFrame: cameraFrame) else {
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.livenessState
                    .unrecoverableStateEncountered(.missingVideoPermission)
            }
            return
        }

        if !viewModel.usesFullScreenCameraPreview {
            avLayer.position = view.center
        }
        self.previewLayer = avLayer
        viewModel.cameraViewRect = CGRect(x: 0, y: 0, width: width, height: height)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layer.insertSublayer(avLayer, at: 0)
            self.view.layoutIfNeeded()

            self.viewModel.startSession()
        }
    }

    var runningFreshness = false
    var hasSentClientInformationEvent = false
    var challengeID = UUID().uuidString
    var initialFace: FaceDetection?
    var videoStartTimeStamp: UInt64?
    var faceMatchStartTime: UInt64?
    var freshnessEventsComplete = false
    var videoSentCount = 0
    var hasSentFinalEvent = false
    var hasSentEmptyFinalVideoEvent = false
    var ovalView: OvalView?


    required init?(coder: NSCoder) { fatalError() }
}

extension _LivenessViewController: FaceLivenessViewControllerPresenter {
    func displaySingleFrame(uiImage: UIImage) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let previewLayer = self.previewLayer else { return }

            if let externalController = self.viewModel.externalFreshnessController,
               externalController.rendersOvalExternally {
                // The RN verification overlay owns this transition. Keep the
                // correctly cropped preview underneath instead of replacing
                // it with the raw 3:4 capture frame.
                self.viewModel.stopRecording()
                return
            }

            let imageView = UIImageView(image: uiImage)
            imageView.frame = self.view.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            self.view.addSubview(imageView)
            (previewLayer as? AVCaptureVideoPreviewLayer)?.session = nil
            previewLayer.removeFromSuperlayer()
            self.viewModel.stopRecording()
        }
    }

    func displayFreshness(colorSequences: [FaceLivenessSession.DisplayColor]) {
        guard viewModel.livenessState.state == .faceMatched else { return }
        if let externalFreshnessController = viewModel.externalFreshnessController {
            displayExternalFreshness(
                colorSequences: colorSequences,
                controller: externalFreshnessController
            )
            return
        }

        self.ovalView?.setNeedsDisplay()
        if let ovalView {
            let freshnessOvalFrame = ovalView.convert(
                ovalView.ovalFrame,
                to: freshnessView
            )
            freshnessView.startOvalPulse(in: freshnessOvalFrame)
        }
        viewModel.livenessState.displayingFreshness()
        self.freshness.showColorSequences(
            colorSequences,
            width: UIScreen.main.bounds.width,
            height: UIScreen.main.bounds.height,
            view: self.freshnessView,
            onNewColor: { [weak self] colorEvent in
                self?.viewModel.sendColorDisplayedEvent(colorEvent)
            },
            onComplete: { [weak self] in
                guard let self else { return }
                self.freshnessView.stopOvalPulse()
                self.freshnessView.removeFromSuperview()

                self.viewModel.handleFreshnessComplete()
            }
        )
    }

    func stopFreshness() {
        // Cancel on this main-actor turn, before returning to oval matching.
        // Enqueuing another block would let an old completion overtake cancellation.
        freshness.cancel()
        viewModel.externalFreshnessController?.cancelPlayback()
        freshnessView.stopOvalPulse()
        // Keep the view available for the next matching attempt.
        freshnessView.clearColors()
    }

    func drawOvalInCanvas(_ ovalRect: CGRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let previewLayer = self.previewLayer else { return }

            let awsOvalFrameInView: CGRect
            if self.viewModel.usesFullScreenCameraPreview {
                awsOvalFrameInView = FaceLivenessPreviewGeometry.aspectFill(
                    rect: ovalRect,
                    sourceSize: self.viewModel.cameraViewRect.size,
                    destinationRect: self.view.bounds
                )
            } else {
                awsOvalFrameInView = previewLayer.convert(ovalRect, to: self.view.layer)
            }

            if let externalController = self.viewModel.externalFreshnessController,
               externalController.rendersOvalExternally {
                let ovalFrameInView: CGRect
                if self.viewModel.usesFullScreenCameraPreview,
                   let configuration = externalController.matchingOvalConfiguration,
                   configuration.referenceViewportWidth > 0,
                   configuration.referenceViewportHeight > 0 {
                    let scale = min(
                        self.view.bounds.width / configuration.referenceViewportWidth,
                        self.view.bounds.height / configuration.referenceViewportHeight
                    )
                    let size = CGSize(
                        width: min(self.view.bounds.width, configuration.width * scale),
                        height: min(self.view.bounds.height, configuration.height * scale)
                    )
                    ovalFrameInView = CGRect(
                        x: awsOvalFrameInView.midX - size.width / 2,
                        y: awsOvalFrameInView.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    )
                    self.viewModel.matchingOvalRectOverride =
                        FaceLivenessPreviewGeometry.inverseAspectFill(
                            rect: ovalFrameInView,
                            sourceSize: self.viewModel.cameraViewRect.size,
                            destinationRect: self.view.bounds
                        )
                } else {
                    ovalFrameInView = awsOvalFrameInView
                    self.viewModel.matchingOvalRectOverride = nil
                }

                externalController.publishOval(
                    frame: ovalFrameInView,
                    viewport: self.view.bounds
                )
                self.ovalRect = ovalRect
                self.ovalExists = true
                return
            }

            let ovalView = OvalView(
                frame: self.view.bounds,
                ovalFrame: awsOvalFrameInView
            )
            ovalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.ovalView = ovalView
            self.view.insertSubview(
                ovalView,
                belowSubview: self.freshnessView
            )

            self.ovalRect = ovalRect
            self.ovalExists = true
        }
    }
    
    func completeNoLightCheck() {
        self.viewModel.completeNoLightCheck()
    }
}

#if DEBUG
struct LivenessViewController_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Camera stand-in + the real `OvalView`. Renders in the simulator.
            ZStack {
                Color.black
                PreviewCameraPlaceholder()
            }
            .edgesIgnoringSafeArea(.all)
            .previewDisplayName("Overlay (simulator)")

            // The real AV layer. Only meaningful when the preview runs on a
            // device — the simulator has no camera, so this stays black.
            CameraView(faceLivenessDetectionViewModel: .preview())
                .edgesIgnoringSafeArea(.all)
                .previewDisplayName("Camera (device only)")
        }
    }
}
#endif
