//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import CoreGraphics
import XCTest
@testable import FaceLiveness

final class FaceLivenessPreviewGeometryTests: XCTestCase {
    func testAspectFillKeepsRectWhenAspectRatioMatches() {
        let rect = CGRect(x: 30, y: 40, width: 120, height: 240)

        let result = FaceLivenessPreviewGeometry.aspectFill(
            rect: rect,
            sourceSize: CGSize(width: 390, height: 520),
            destinationRect: CGRect(x: 0, y: 0, width: 390, height: 520)
        )

        XCTAssertEqual(result, rect)
    }

    func testAspectFillAppliesSameScaleAndCropAsFullScreenPreview() {
        let result = FaceLivenessPreviewGeometry.aspectFill(
            rect: CGRect(x: 95, y: 100, width: 200, height: 320),
            sourceSize: CGSize(width: 390, height: 520),
            destinationRect: CGRect(x: 0, y: 0, width: 390, height: 844)
        )

        let expectedScale = 844.0 / 520.0
        let expectedOffsetX = (390.0 - 390.0 * expectedScale) / 2.0
        XCTAssertEqual(result.minX, expectedOffsetX + 95.0 * expectedScale, accuracy: 0.001)
        XCTAssertEqual(result.minY, 100.0 * expectedScale, accuracy: 0.001)
        XCTAssertEqual(result.width, 200.0 * expectedScale, accuracy: 0.001)
        XCTAssertEqual(result.height, 320.0 * expectedScale, accuracy: 0.001)
    }

    func testInverseAspectFillRestoresSourceRect() {
        let sourceRect = CGRect(x: 72, y: 124, width: 260, height: 390)
        let sourceSize = CGSize(width: 480, height: 640)
        let destination = CGRect(x: 0, y: 0, width: 393, height: 852)

        let displayedRect = FaceLivenessPreviewGeometry.aspectFill(
            rect: sourceRect,
            sourceSize: sourceSize,
            destinationRect: destination
        )
        let restoredRect = FaceLivenessPreviewGeometry.inverseAspectFill(
            rect: displayedRect,
            sourceSize: sourceSize,
            destinationRect: destination
        )

        XCTAssertEqual(restoredRect.minX, sourceRect.minX, accuracy: 0.001)
        XCTAssertEqual(restoredRect.minY, sourceRect.minY, accuracy: 0.001)
        XCTAssertEqual(restoredRect.width, sourceRect.width, accuracy: 0.001)
        XCTAssertEqual(restoredRect.height, sourceRect.height, accuracy: 0.001)
    }
}
