//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import FaceLiveness
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin

@MainActor
final class FreshnessRetryTests: XCTestCase {
    func testHostCompletionCleanupCannotCancelNativeCompletion() async throws {
        let controller = FaceLivenessExternalFreshnessController()
        var completed = false
        var cancellations = 0
        controller.onCancelled = { _ in cancellations += 1 }
        controller.onCompleted = { _ in controller.cancelPlayback() }
        controller.play([color(duration: 10)],
                        onAcknowledged: { _ in }, onComplete: { completed = true })
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(completed)
        XCTAssertEqual(cancellations, 0)
        controller.onCompleted = nil
    }

    func testStaleReadinessCannotStartReplacementSequence() async throws {
        let controller = FaceLivenessExternalFreshnessController()
        var preparedIDs: [UUID] = []
        var cancelledIDs: [UUID] = []
        var started = 0
        controller.onFreshnessSequencePrepared = { preparedIDs.append($0.sequenceID) }
        controller.onCancelled = { cancelledIDs.append($0) }
        controller.onStarted = { _ in started += 1 }
        controller.play([color(duration: 10)], onAcknowledged: { _ in }, onComplete: {})
        let first = try XCTUnwrap(preparedIDs.first)
        controller.cancelPlayback()
        controller.cancelPlayback()

        let completed = expectation(description: "Replacement sequence completes")
        var colorIndices: [Int] = []
        controller.play([color(duration: 10)],
                        onAcknowledged: { colorIndices.append($0.sequenceNumber) },
                        onComplete: { completed.fulfill() })
        let second = try XCTUnwrap(preparedIDs.last)
        XCTAssertNotEqual(first, second)
        controller.acknowledgeFreshnessReady(sequenceID: first)
        XCTAssertEqual(started, 0)
        controller.acknowledgeFreshnessReady(sequenceID: second)
        controller.acknowledgeFreshnessReady(sequenceID: second)
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(started, 1)
        XCTAssertEqual(colorIndices, [0])
        XCTAssertEqual(cancelledIDs, [first])
        controller.cancelPlayback()
        XCTAssertEqual(cancelledIDs, [first], "Completed playback is not cancelled")
    }

    func testCancellingActiveExternalPlaybackSuppressesRemainingEvents() async throws {
        let controller = FaceLivenessExternalFreshnessController()
        let firstColor = expectation(description: "First color")
        let unexpected = expectation(description: "No subsequent color or completion")
        unexpected.isInverted = true
        var cancellations = 0
        controller.onCancelled = { _ in cancellations += 1 }
        controller.play([color(duration: 100), color(duration: 10)],
                        onAcknowledged: { event in
                            if event.sequenceNumber == 0 {
                                controller.cancelPlayback()
                                firstColor.fulfill()
                            } else {
                                unexpected.fulfill()
                            }
                        }, onComplete: { unexpected.fulfill() })
        await fulfillment(of: [firstColor, unexpected], timeout: 0.3)
        XCTAssertEqual(cancellations, 1)
    }

    func testExternalCancellationFromStartedCallbackPreventsColorEvents() async throws {
        let controller = FaceLivenessExternalFreshnessController()
        var emittedColors = 0
        var completed = false
        controller.onStarted = { _ in controller.cancelPlayback() }
        controller.play([color(duration: 10)],
                        onAcknowledged: { _ in emittedColors += 1 },
                        onComplete: { completed = true })
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(emittedColors, 0)
        XCTAssertFalse(completed)
        controller.onStarted = nil
    }

    func testMinimumFaceSizeOnlyRestrictsAWSMatchesAndRequiresBothDimensions() {
        let oval = CGRect(x: 0, y: 0, width: 100, height: 100)
        let controller = FaceLivenessExternalFreshnessController(minimumFaceSizeRatio: 0.95)
        for size in [CGSize(width: 85.4, height: 79.7), CGSize(width: 85, height: 76),
                     CGSize(width: 94.9, height: 100), CGSize(width: 100, height: 94.9)] {
            let result = controller.applyingMinimumFaceSize(to: .match,
                face: CGRect(origin: .zero, size: size), oval: oval)
            guard case .tooFar = result else { return XCTFail("Both dimensions must reach 95%") }
        }
        let filled = CGRect(x: 0, y: 0, width: 95, height: 95)
        XCTAssertEqual(controller.applyingMinimumFaceSize(to: .match, face: filled, oval: oval), .match)
        let rejected = Instructor.Instruction.tooClose(nearnessPercentage: 1)
        XCTAssertEqual(controller.applyingMinimumFaceSize(to: rejected, face: filled, oval: oval), rejected)
        let unchanged = FaceLivenessExternalFreshnessController()
        XCTAssertEqual(unchanged.applyingMinimumFaceSize(to: .match,
            face: CGRect(x: 0, y: 0, width: 85, height: 76), oval: oval), .match)
    }

    func testMinimumFaceSizeAboveOneIsNotClamped() {
        let controller = FaceLivenessExternalFreshnessController(minimumFaceSizeRatio: 1.1)
        XCTAssertEqual(controller.minimumFaceSizeRatio, 1.1)
        let oval = CGRect(x: 0, y: 0, width: 100, height: 100)
        for size in [CGSize(width: 100, height: 100), CGSize(width: 109.9, height: 110),
                     CGSize(width: 110, height: 109.9)] {
            let result = controller.applyingMinimumFaceSize(to: .match,
                face: CGRect(origin: .zero, size: size), oval: oval)
            guard case .tooFar = result else { return XCTFail("Both dimensions must reach 110%") }
        }
        let filled = CGRect(x: -5, y: -5, width: 110, height: 110)
        XCTAssertEqual(controller.applyingMinimumFaceSize(to: .match, face: filled, oval: oval), .match)
        let tooClose = Instructor.Instruction.tooClose(nearnessPercentage: 1)
        XCTAssertEqual(controller.applyingMinimumFaceSize(to: tooClose, face: filled, oval: oval), tooClose)
    }

    func testApproachProgressDoesNotJumpBackWhenAWSMatchesBeforeTheSizeFloor() {
        let controller = FaceLivenessExternalFreshnessController(minimumFaceSizeRatio: 1.1)
        let oval = CGRect(x: 0, y: 0, width: 100, height: 100)
        let face = CGRect(x: 0, y: 0, width: 95, height: 90)
        let approaching = controller.applyingMinimumFaceSize(
            to: .tooFar(text: "Move closer", nearnessPercentage: 1), face: face, oval: oval)
        let awsMatched = controller.applyingMinimumFaceSize(to: .match, face: face, oval: oval)
        guard case .tooFar(let text, let before) = approaching,
              case .tooFar(_, let after) = awsMatched else {
            return XCTFail("The size floor must still require approaching")
        }
        XCTAssertEqual(text, "Move closer")
        XCTAssertEqual(before, 0.9 / 1.1, accuracy: 0.0001)
        XCTAssertEqual(before, after, accuracy: 0.0001)

        let earlier = controller.applyingMinimumFaceSize(
            to: .tooFar(nearnessPercentage: 0.5), face: face, oval: oval)
        guard case .tooFar(_, let progress) = earlier else { return XCTFail("Keep AWS instruction") }
        XCTAssertEqual(progress, 0.5, "The RN cap must not inflate AWS progress")

        let defaultController = FaceLivenessExternalFreshnessController()
        let unchanged = defaultController.applyingMinimumFaceSize(
            to: .tooFar(nearnessPercentage: 1), face: face, oval: oval)
        guard case .tooFar(_, let originalProgress) = unchanged else { return XCTFail("Keep defaults") }
        XCTAssertEqual(originalProgress, 1)
    }

    private func color(duration: Double, scroll: Bool = false) -> FaceLivenessSession.DisplayColor {
        .init(rgb: .init(red: 1, green: 0, blue: 0, _values: [255, 0, 0]),
              duration: duration, shouldScroll: scroll)
    }
}
