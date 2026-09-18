//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import AWSClientRuntime
import protocol AWSPluginsCore.AWSCredentialsProvider
import AWSPredictionsPlugin
import AVFoundation
import Amplify
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin

/// Type-erases a SwiftUI view builder so host applications can provide their
/// own presentation without exposing FaceLiveness's internal state machine.
public struct FaceLivenessViewFactory<Context> {
    let makeView: (Context) -> AnyView

    public init<Content: View>(
        @ViewBuilder _ makeView: @escaping (Context) -> Content
    ) {
        self.makeView = { context in AnyView(makeView(context)) }
    }
}

public struct FaceLivenessGetReadyContext {
    public let showsPhotosensitivityWarning: Bool
    public let onBegin: () -> Void
    public let onCancel: () -> Void
}

public struct FaceLivenessShootingContext {
    public let instruction: String
    public let progress: Double
    public let showsGuideOval: Bool
    public let onCancel: () -> Void
}

public struct FaceLivenessFreshnessContext {
    public let instruction: String
    public let onCancel: () -> Void
}

public struct FaceLivenessVerificationContext {
    public let instruction: String
    public let onCancel: () -> Void
}

/// Views supplied by a host application without coupling FaceLiveness to the
/// host's UI dependencies. Camera capture, oval tracking, and the freshness
/// challenge remain owned by FaceLiveness.
public struct FaceLivenessViewCustomization {
    let getReadyView: FaceLivenessViewFactory<FaceLivenessGetReadyContext>?
    let shootingOverlay: FaceLivenessViewFactory<FaceLivenessShootingContext>?
    let freshnessOverlay: FaceLivenessViewFactory<FaceLivenessFreshnessContext>?
    let verificationOverlay: FaceLivenessViewFactory<FaceLivenessVerificationContext>?
    let externalFreshnessController: FaceLivenessExternalFreshnessController?

    public init() {
        self.getReadyView = nil
        self.shootingOverlay = nil
        self.freshnessOverlay = nil
        self.verificationOverlay = nil
        self.externalFreshnessController = nil
    }

    public init(
        getReadyView: FaceLivenessViewFactory<FaceLivenessGetReadyContext>? = nil,
        shootingOverlay: FaceLivenessViewFactory<FaceLivenessShootingContext>? = nil,
        freshnessOverlay: FaceLivenessViewFactory<FaceLivenessFreshnessContext>? = nil,
        verificationOverlay: FaceLivenessViewFactory<FaceLivenessVerificationContext>? = nil,
        externalFreshnessController: FaceLivenessExternalFreshnessController? = nil
    ) {
        self.getReadyView = getReadyView
        self.shootingOverlay = shootingOverlay
        self.freshnessOverlay = freshnessOverlay
        self.verificationOverlay = verificationOverlay
        self.externalFreshnessController = externalFreshnessController
    }
}

public struct FaceLivenessDetectorView: View {
    @StateObject var viewModel: FaceLivenessDetectionViewModel
    @Binding var isPresented: Bool
    @State var displayState: DisplayState = .awaitingChallengeType
    @State var displayingCameraPermissionsNeededAlert = false
    @State private var brightnessState = BrightnessState()
    @StateObject private var orientationObserver = InterfaceOrientationObserver()

    private final class BrightnessState {
        var original: CGFloat?
    }

    let disableStartView: Bool
    let challengeOptions: ChallengeOptions
    let viewCustomization: FaceLivenessViewCustomization
    let onCompletion: (Result<Void, FaceLivenessDetectionError>) -> Void

    let sessionTask: Task<FaceLivenessSession, Error>

    public init(
        sessionID: String,
        credentialsProvider: AWSCredentialsProvider? = nil,
        region: String,
        disableStartView: Bool = false,
        challengeOptions: ChallengeOptions = .init(),
        viewCustomization: FaceLivenessViewCustomization = .init(),
        isPresented: Binding<Bool>,
        onCompletion: @escaping (Result<Void, FaceLivenessDetectionError>) -> Void
    ) {        
        self.disableStartView = disableStartView
        self._isPresented = isPresented
        self.onCompletion = onCompletion
        self.challengeOptions = challengeOptions
        self.viewCustomization = viewCustomization

        self.sessionTask = Task {
            let session = try await AWSPredictionsPlugin.startFaceLivenessSession(
                withID: sessionID,
                credentialsProvider: credentialsProvider,
                region: region,
                completion: map(detectionCompletion: onCompletion)
            )
            return session
        }

        let faceDetector = try! FaceDetectorShortRange.Model()
        let faceInOvalStateMatching = FaceInOvalMatching(
            instructor: Instructor()
        )

        let videoChunker = VideoChunker(
            assetWriter: LivenessAVAssetWriter(),
            assetWriterDelegate: VideoChunker.AssetWriterDelegate(),
            assetWriterInput: LivenessAVAssetWriterInput()
        )

        self._viewModel = StateObject(
            wrappedValue: .init(
                faceDetector: faceDetector,
                faceInOvalMatching: faceInOvalStateMatching,
                videoChunker: videoChunker,
                closeButtonAction: { onCompletion(.failure(.userCancelled)) },
                sessionID: sessionID,
                isPreviewScreenEnabled: !disableStartView,
                challengeOptions: challengeOptions,
                externalFreshnessController: viewCustomization.externalFreshnessController
            )
        )
    }
    
    init(
        sessionID: String,
        credentialsProvider: AWSCredentialsProvider? = nil,
        region: String,
        disableStartView: Bool = false,
        challengeOptions: ChallengeOptions = .init(),
        viewCustomization: FaceLivenessViewCustomization = .init(),
        isPresented: Binding<Bool>,
        onCompletion: @escaping (Result<Void, FaceLivenessDetectionError>) -> Void,
        captureSession: LivenessCaptureSession
    ) {
        self.disableStartView = disableStartView
        self._isPresented = isPresented
        self.onCompletion = onCompletion
        self.challengeOptions = challengeOptions
        self.viewCustomization = viewCustomization

        self.sessionTask = Task {
            let session = try await AWSPredictionsPlugin.startFaceLivenessSession(
                withID: sessionID,
                credentialsProvider: credentialsProvider,
                region: region,
                completion: map(detectionCompletion: onCompletion)
            )
            return session
        }

        let faceInOvalStateMatching = FaceInOvalMatching(
            instructor: Instructor()
        )

        self._viewModel = StateObject(
            wrappedValue: .init(
                faceDetector: captureSession.outputSampleBufferCapturer!.faceDetector,
                faceInOvalMatching: faceInOvalStateMatching,
                videoChunker: captureSession.outputSampleBufferCapturer!.videoChunker,
                closeButtonAction: { onCompletion(.failure(.userCancelled)) },
                sessionID: sessionID,
                isPreviewScreenEnabled: !disableStartView,
                challengeOptions: challengeOptions,
                externalFreshnessController: viewCustomization.externalFreshnessController
            )
        )
    }

    public var body: some View {
        ZStack {
            // `RotateDeviceView` covers the content but not the accessibility tree
            content
                .accessibilityHidden(orientationObserver.decision == .blockUntilPortrait)

            if orientationObserver.decision == .blockUntilPortrait {
                RotateDeviceView(onClose: cancelFromRotatePrompt)
            }
        }
        .background(
            InterfaceOrientationReader(
                onTransition: orientationObserver.beginTransition(with:),
                onSettled: orientationObserver.settle(in:)
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .onChange(of: orientationObserver.orientation) { _ in
            interruptCheckIfOrientationUnsupported()
            advanceIfWaitingOnPortrait()
        }
        .onReceive(viewModel.$livenessState) { output in
            // one observer for every display state, so any exit that reaches a terminal
            // state dismisses and fires the host's completion exactly once
            switch output.state {
            case .completed:
                isPresented = false
                onCompletion(.success(()))
            case .encounteredUnrecoverableError(let error):
                let closeCode = error.webSocketCloseCode ?? .normalClosure
                viewModel.livenessService?.closeSocket(with: closeCode)
                isPresented = false
                onCompletion(.failure(mapError(error)))
            default:
                break
            }
        }
        .onDisappear {
            restoreOriginalBrightness()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch displayState {
        case .awaitingChallengeType:
            LoadingPageView()
            .onAppear {
                Task {
                    do {
                        let session = try await sessionTask.value
                        viewModel.livenessService = session
                        viewModel.registerServiceEvents(onChallengeTypeReceived: { challenge in
                            self.displayState = DisplayState.awaitingCameraPermission(challenge)
                        })
                        viewModel.initializeLivenessStream()
                    } catch let error as FaceLivenessDetectionError {
                        switch error {
                        case .unknown:
                            viewModel.livenessState.unrecoverableStateEncountered(.unknown)
                        case .sessionTimedOut,
                             .faceInOvalMatchExceededTimeLimitError,
                             .countdownFaceTooClose,
                             .countdownMultipleFaces,
                             .countdownNoFace:
                            viewModel.livenessState.unrecoverableStateEncountered(.timedOut)
                        case .cameraPermissionDenied:
                            viewModel.livenessState.unrecoverableStateEncountered(.missingVideoPermission)
                        case .userCancelled:
                            viewModel.livenessState.unrecoverableStateEncountered(.userCancelled)
                        case .socketClosed:
                            viewModel.livenessState.unrecoverableStateEncountered(.socketClosed)
                        case .cameraNotAvailable:
                            viewModel.livenessState.unrecoverableStateEncountered(.cameraNotAvailable)
                        default:
                            viewModel.livenessState.unrecoverableStateEncountered(.couldNotOpenStream)
                        }
                    } catch {
                        viewModel.livenessState.unrecoverableStateEncountered(.couldNotOpenStream)
                    }
                    
                    DispatchQueue.main.async {
                        if let faceDetector = viewModel.faceDetector as? FaceDetectorShortRange.Model {
                            faceDetector.setFaceDetectionSessionConfigurationWrapper(configuration: viewModel)
                        }
                    }
                }
            }
        case .awaitingCameraPermission(let challenge):
            CameraPermissionView(displayingCameraPermissionsNeededAlert: $displayingCameraPermissionsNeededAlert)
                .onAppear {
                    checkCameraPermission(for: challenge)
                }
        case .awaitingLivenessSession:
            Color.clear
                .onAppear {
                    advanceIfWaitingOnPortrait()
                }
        case .displayingGetReadyView(let challenge, let cameraPosition):
            let onBegin = {
                guard displayState != .displayingLiveness,
                      orientationObserver.decision == .proceed else { return }
                displayState = .displayingLiveness
            }

            Group {
                if viewCustomization.externalFreshnessController != nil,
                   let getReadyView = viewCustomization.getReadyView {
                    getReadyView.makeView(
                        FaceLivenessGetReadyContext(
                            showsPhotosensitivityWarning: challenge == .faceMovementAndLightChallenge("2.0.0"),
                            onBegin: onBegin,
                            onCancel: viewModel.closeButtonAction
                        )
                    )
                } else {
                    GetReadyPageView(
                        onBegin: onBegin,
                        beginCheckButtonDisabled: false,
                        challenge: challenge,
                        cameraPosition: cameraPosition
                    )
                }
            }
            .onAppear {
                setBrightnessToMax()
            }
        case .displayingLiveness:
            _FaceLivenessDetectionView(
                viewModel: viewModel,
                viewCustomization: viewCustomization,
                videoView: {
                    CameraView(
                        faceLivenessDetectionViewModel: viewModel
                    )
                }
            )
            .onAppear {
                setBrightnessToMax()
            }
            .onDisappear() {
                viewModel.stopRecording()
            }
        }
    }

    /// Advances from `.awaitingLivenessSession` to the get ready screen (or straight to the
    /// check) once the interface is portrait. Holding here keeps the session reusable.
    private func advanceIfWaitingOnPortrait() {
        guard case .awaitingLivenessSession(let challenge) = displayState else { return }
        guard orientationObserver.decision == .proceed else { return }

        let newState = disableStartView
        ? DisplayState.displayingLiveness
        : DisplayState.displayingGetReadyView(challenge, challengeOptions.camera(for: challenge))
        guard self.displayState != newState else { return }
        self.displayState = newState
    }

    /// Ends a running check when the interface leaves portrait, the same way scene deactivation
    /// does. Deferred so the state change lands outside the view update.
    private func interruptCheckIfOrientationUnsupported() {
        guard orientationObserver.decision == .blockUntilPortrait,
              displayState == .displayingLiveness
        else { return }

        DispatchQueue.main.async {
            viewModel.endCheck(with: .viewResignation)
        }
    }

    /// Cancels from the rotate prompt through the state machine, like the close button, so a
    /// pending rotation interrupt finds the check already finished.
    private func cancelFromRotatePrompt() {
        viewModel.endCheck(with: .userCancelled)
    }

    /// Overrides the device screen brightness to maximum for the liveness check,
    /// capturing the user's original brightness once so it can be restored on exit.
    private func setBrightnessToMax() {
        DispatchQueue.main.async {
            if brightnessState.original == nil {
                brightnessState.original = UIScreen.main.brightness
            }
            UIScreen.main.brightness = 1.0
        }
    }

    /// Restores the brightness captured in `setBrightnessToMax()`. Invoked when the
    /// view leaves the hierarchy, so it runs on every exit path (success, cancel, error).
    private func restoreOriginalBrightness() {
        DispatchQueue.main.async {
            guard let original = brightnessState.original else { return }
            UIScreen.main.brightness = original
            brightnessState.original = nil
        }
    }

    func mapError(_ livenessError: LivenessStateMachine.LivenessError) -> FaceLivenessDetectionError {
        switch livenessError {
        case .userCancelled:
            return .userCancelled
        case .viewResignation:
            return .sessionInterrupted
        case .timedOut:
            return .faceInOvalMatchExceededTimeLimitError
        case .couldNotOpenStream, .socketClosed:
            return .socketClosed
        case .cameraNotAvailable:
            return .cameraNotAvailable
        default:
            return .cameraPermissionDenied
        }
    }

    private func requestCameraPermission(for challenge: Challenge) {
        AVCaptureDevice.requestAccess(
            for: .video,
            completionHandler: { accessGranted in
                guard accessGranted == true else { return }
                displayState = .awaitingLivenessSession(challenge)
            }
        )
    }

    private func alertCameraAccessNeeded() {
        displayingCameraPermissionsNeededAlert = true
    }
    
    private func checkCameraPermission(for challenge: Challenge) {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraAuthorizationStatus {
        case .notDetermined:
            requestCameraPermission(for: challenge)
        case .restricted, .denied:
            alertCameraAccessNeeded()
        case .authorized:
            displayState = .awaitingLivenessSession(challenge)
        @unknown default:
            break
        }
    }
}

enum DisplayState: Equatable {
    case awaitingChallengeType
    case awaitingCameraPermission(Challenge)
    case awaitingLivenessSession(Challenge)
    case displayingGetReadyView(Challenge, LivenessCamera)
    case displayingLiveness
    
    static func == (lhs: DisplayState, rhs: DisplayState) -> Bool {
        switch (lhs, rhs) {
        case (.awaitingChallengeType, .awaitingChallengeType):
            return true
        case (let .awaitingLivenessSession(c1), let .awaitingLivenessSession(c2)):
            return c1 == c2
        case (let .displayingGetReadyView(c1, position1), let .displayingGetReadyView(c2, position2)):
            return c1 == c2 && position1 == position2
        case (.displayingLiveness, .displayingLiveness):
            return true
        case (.awaitingCameraPermission, .awaitingCameraPermission):
            return true
        default:
            return false
        }
    }
}

enum InstructionState {
    case none
    case display(text: String)
}

private func map(detectionCompletion: @escaping (Result<Void, FaceLivenessDetectionError>) -> Void) -> ((Result<Void, FaceLivenessSessionError>) -> Void) {
    { result in
        switch result {
        case .success:
            detectionCompletion(.success(()))
        case .failure(.invalidRegion):
            detectionCompletion(.failure(.invalidRegion))
        case .failure(.accessDenied):
            detectionCompletion(.failure(.accessDenied))
        case .failure(.validation):
            detectionCompletion(.failure(.validation))
        case .failure(.internalServer):
            detectionCompletion(.failure(.internalServer))
        case .failure(.throttling):
            detectionCompletion(.failure(.throttling))
        case .failure(.serviceQuotaExceeded):
            detectionCompletion(.failure(.serviceQuotaExceeded))
        case .failure(.serviceUnavailable):
            detectionCompletion(.failure(.serviceUnavailable))
        case .failure(.sessionNotFound):
            detectionCompletion(.failure(.sessionNotFound))
        case .failure(.invalidSignature):
            detectionCompletion(.failure(.invalidSignature))
        default:
            detectionCompletion(.failure(.unknown))
        }
    }
}

public enum LivenessCamera {
    case front
    case back
}

public struct ChallengeOptions {
    let faceMovementChallengeOption: FaceMovementChallengeOption
    let faceMovementAndLightChallengeOption: FaceMovementAndLightChallengeOption
    
    public init(faceMovementChallengeOption: FaceMovementChallengeOption = .init(camera: .front),
                faceMovementAndLightChallengeOption: FaceMovementAndLightChallengeOption = .init()) {
        self.faceMovementChallengeOption = faceMovementChallengeOption
        self.faceMovementAndLightChallengeOption = faceMovementAndLightChallengeOption
    }

    /// The camera configured for `challenge`.
    func camera(for challenge: Challenge) -> LivenessCamera {
        switch challenge {
        case .faceMovementChallenge:
            return faceMovementChallengeOption.camera
        case .faceMovementAndLightChallenge:
            return faceMovementAndLightChallengeOption.camera
        }
    }
}

public struct FaceMovementChallengeOption {
    let challenge: Challenge
    let camera: LivenessCamera
    
    public init(camera: LivenessCamera) {
        self.challenge = .faceMovementChallenge("1.0.0")
        self.camera = camera
    }
}

public struct FaceMovementAndLightChallengeOption {
    let challenge: Challenge
    let camera: LivenessCamera

    public init() {
        self.challenge = .faceMovementAndLightChallenge("2.0.0")
        self.camera = .front
    }
}

#if DEBUG
/// `FaceLivenessDetectorView` itself can't be previewed: its initializer opens a
/// live AWS session, so the canvas would only ever show the connecting spinner.
/// These previews render the screens it drives, one per `DisplayState`.
struct FaceLivenessDetectorView_Previews: PreviewProvider {
    static func liveness(_ state: LivenessStateMachine.State) -> some View {
        _FaceLivenessDetectionView(
            viewModel: .preview(state: state),
            videoView: { PreviewCameraPlaceholder() }
        )
    }

    static var previews: some View {
        Group {
            LoadingPageView()
                .previewDisplayName("1 · Connecting")

            CameraPermissionView()
                .previewDisplayName("2 · Camera permission")

            GetReadyPageView(
                onBegin: {},
                challenge: .faceMovementAndLightChallenge("2.0.0"),
                cameraPosition: .front
            )
            .previewDisplayName("3 · Get ready")

            liveness(.awaitingFaceInOvalMatch(.moveFaceCloser, 0.4))
                .previewDisplayName("4 · Liveness (move closer)")

            liveness(.displayingFreshness)
                .previewDisplayName("5 · Liveness (hold still)")
        }
    }
}
#endif
