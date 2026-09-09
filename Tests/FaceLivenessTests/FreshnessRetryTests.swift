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

    func testNativeRestartDoesNotReviveCancelledCallbacks() async throws {
        let freshness = Freshness()
        let view = FreshnessView()
        var oldEvents = 0
        var oldCompleted = false
        freshness.showColorSequences(
            [color(duration: 100), color(duration: 100, scroll: true)],
            width: 100, height: 100, view: view,
            onNewColor: { _ in oldEvents += 1 },
            onComplete: { oldCompleted = true }
        )
        freshness.cancel()
        freshness.showColorSequences(
            [color(duration: 5_000), color(duration: 100, scroll: true)],
            width: 100, height: 100, view: view,
            onNewColor: { _ in }, onComplete: {}
        )
        defer { freshness.cancel() }

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(oldEvents, 1, "Cancelled callbacks must not read the new sequence")
        XCTAssertFalse(oldCompleted)
    }

    private func color(duration: Double, scroll: Bool = false) -> FaceLivenessSession.DisplayColor {
        .init(rgb: .init(red: 1, green: 0, blue: 0, _values: [255, 0, 0]),
              duration: duration, shouldScroll: scroll)
    }
}
