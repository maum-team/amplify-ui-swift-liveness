import XCTest
@testable import FaceLiveness

@MainActor
final class FaceLivenessPresentationControllerTests: XCTestCase {
    func testObservingFaceLossDoesNotRestartFreshness() {
        let controller = FaceLivenessPresentationController()
        var events: [FaceLivenessUIState] = []
        controller.onStateChanged = { events.append($0) }
        var state = LivenessStateMachine(state: .displayingFreshness)

        controller.publish(state)
        state.faceNotMatched(reason: .noFace)
        controller.publish(state)

        XCTAssertEqual(state.state, .displayingFreshness)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.phase, "freshness")
        XCTAssertEqual(events.first?.isRecording, true)
    }

    func testBothChallengeTypesPublishVerificationWithoutChangingTheState() {
        for completion in [LivenessStateMachine.State.completedDisplayingFreshness, .completedNoLightCheck] {
            let controller = FaceLivenessPresentationController()
            var event: FaceLivenessUIState?
            controller.onStateChanged = { event = $0 }
            let state = LivenessStateMachine(state: completion)

            controller.publish(state)

            XCTAssertEqual(state.state, completion)
            XCTAssertEqual(event?.phase, "verifying")
            XCTAssertEqual(event?.progress, 1)
            XCTAssertEqual(event?.isRecording, false)
        }
    }

    func testPublishesUpstreamPositioningProgressAndRecordingFlag() {
        let controller = FaceLivenessPresentationController()
        var events: [FaceLivenessUIState] = []
        controller.onStateChanged = { events.append($0) }

        controller.publish(.init(state: .pendingFacePreparedConfirmation(.noFace)))
        controller.publish(.init(state: .awaitingFaceInOvalMatch(.moveFaceCloser, 0.42)))

        XCTAssertEqual(events.map(\.isRecording), [false, true])
        XCTAssertEqual(events.last?.progress, 0.42)
        XCTAssertEqual(events.last?.instruction, LivenessStateMachine.FaceNotPreparedReason.moveFaceCloser.localizedValue)
    }

    func testOvalCoordinatesFollowTheViewportAndIgnoreEmptyLayouts() throws {
        let controller = FaceLivenessPresentationController()
        var events: [FaceLivenessPresentationOval] = []
        controller.onOvalChanged = { events.append($0) }
        let frame = CGRect(x: 110, y: 220, width: 200, height: 400)
        let viewport = CGRect(x: 10, y: 20, width: 400, height: 800)

        controller.publishOval(frame: frame, viewport: .zero)
        controller.publishOval(frame: frame, viewport: viewport)
        controller.publishOval(frame: frame, viewport: viewport)

        XCTAssertEqual(events.count, 1)
        let oval = try XCTUnwrap(events.first)
        XCTAssertEqual(oval.x, 0.25)
        XCTAssertEqual(oval.y, 0.25)
        XCTAssertEqual(oval.width, 0.5)
        XCTAssertEqual(oval.height, 0.5)
    }
}
