import XCTest
@testable import FaceLiveness
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin

@MainActor
final class FaceLivenessColorRendererTests: XCTestCase {
    func testPreservesAWSColorsOrderDurationsAndScrollFlags() throws {
        let renderer = FaceLivenessColorRenderer()
        var sequence: FaceLivenessColorSequence?
        renderer.onSequencePrepared = { sequence = $0 }
        var starts = 0

        renderer.prepare(colors()) { _ in starts += 1 }

        let frames = try XCTUnwrap(sequence).frames
        XCTAssertEqual(frames.map(\.currentColor), [[0, 0, 0], [255, 255, 255]])
        XCTAssertEqual(frames.map(\.previousColor), [[0, 0, 0], [0, 0, 0]])
        XCTAssertEqual(frames.map(\.durationMilliseconds), [75, 475])
        XCTAssertEqual(frames.map(\.shouldScroll), [false, true])
        XCTAssertEqual(starts, 0, "Playback waits until the host surface is ready")
    }

    func testOnlyMatchingReadyAcknowledgementStartsUpstreamPlaybackOnce() throws {
        let renderer = FaceLivenessColorRenderer()
        var sequenceID: UUID?
        renderer.onSequencePrepared = { sequenceID = $0.sequenceID }
        var starts = 0
        renderer.prepare(colors()) { _ in starts += 1 }

        renderer.acknowledgeReady(sequenceID: UUID())
        XCTAssertEqual(starts, 0)
        let id = try XCTUnwrap(sequenceID)
        renderer.acknowledgeReady(sequenceID: id)
        renderer.acknowledgeReady(sequenceID: id)

        XCTAssertEqual(starts, 1)
    }

    func testCancelledSurfaceCannotStartOrCompleteLater() throws {
        let renderer = FaceLivenessColorRenderer()
        var sequenceID: UUID?
        renderer.onSequencePrepared = { sequenceID = $0.sequenceID }
        var starts = 0
        var completions = 0
        var cancellations = 0
        renderer.onCompleted = { _, _ in completions += 1 }
        renderer.onCancelled = { _ in cancellations += 1 }
        renderer.prepare(colors()) { _ in starts += 1 }
        let id = try XCTUnwrap(sequenceID)

        renderer.cancel()
        renderer.cancel()
        renderer.acknowledgeReady(sequenceID: id)
        renderer.complete(sequenceID: id)

        XCTAssertEqual(starts, 0)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(cancellations, 1)
    }

    func testCompletionIsNotReportedAsCancellation() throws {
        let renderer = FaceLivenessColorRenderer()
        var sequenceID: UUID?
        renderer.onSequencePrepared = { sequenceID = $0.sequenceID }
        var completions = 0
        var cancellations = 0
        renderer.onCompleted = { _, _ in completions += 1 }
        renderer.onCancelled = { _ in cancellations += 1 }
        renderer.prepare(colors()) { _ in }
        let id = try XCTUnwrap(sequenceID)
        renderer.acknowledgeReady(sequenceID: id)

        renderer.complete(sequenceID: id)
        renderer.complete(sequenceID: id)
        renderer.cancel()

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(cancellations, 0)
    }

    func testSkiaReadinessStillReachesUpstreamVideoFinalization() throws {
        let renderer = FaceLivenessColorRenderer()
        let controller = FaceLivenessPresentationController(colorRenderer: renderer)
        let viewModel = LivenessGeometryFixture.makeViewModel(
            presenter: MockLivenessViewControllerPresenter(), kind: .faceMovementAndLight
        )
        viewModel.livenessState = .init(state: .faceMatched)
        let viewController = _LivenessViewController(
            viewModel: viewModel, presentationController: controller
        )
        var sequenceID: UUID?
        var preparedCount = 0
        renderer.onSequencePrepared = {
            sequenceID = $0.sequenceID
            preparedCount += 1
        }
        let completed = expectation(description: "upstream Freshness completes")
        renderer.onCompleted = { _, _ in completed.fulfill() }

        viewController.displayFreshness(colorSequences: colors())
        XCTAssertTrue(viewController.freshnessView.isHidden)
        XCTAssertEqual(viewModel.videoChunker.state, .pending)
        viewModel.livenessState.faceNotMatched(reason: .noFace)
        renderer.acknowledgeReady(sequenceID: try XCTUnwrap(sequenceID))
        wait(for: [completed], timeout: 3)

        XCTAssertEqual(preparedCount, 1, "Face loss must not prepare a second color sequence")
        XCTAssertEqual(viewModel.videoChunker.state, .awaitingSingleFrame,
                       "The upstream completion must still finish the video")
    }

    private func colors() -> [FaceLivenessSession.DisplayColor] {
        [
            .init(rgb: .init(red: 0, green: 0, blue: 0, _values: [0, 0, 0]),
                  duration: 75, shouldScroll: false),
            .init(rgb: .init(red: 1, green: 1, blue: 1, _values: [255, 255, 255]),
                  duration: 475, shouldScroll: true)
        ]
    }
}
