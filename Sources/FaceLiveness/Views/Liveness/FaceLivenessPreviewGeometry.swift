//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import CoreGraphics

/// Geometry for mapping between canonical liveness capture coordinates and an
/// edge-to-edge aspect-fill preview. The inverse mapping is used only when an
/// external host explicitly opts into a local matching-oval override.
enum FaceLivenessPreviewGeometry {
    static func aspectFill(
        rect: CGRect,
        sourceSize: CGSize,
        destinationRect: CGRect
    ) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              destinationRect.width > 0,
              destinationRect.height > 0 else {
            return rect
        }

        let scale = max(
            destinationRect.width / sourceSize.width,
            destinationRect.height / sourceSize.height
        )
        let renderedSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let offset = CGPoint(
            x: destinationRect.minX + (destinationRect.width - renderedSize.width) / 2,
            y: destinationRect.minY + (destinationRect.height - renderedSize.height) / 2
        )

        return CGRect(
            x: offset.x + rect.minX * scale,
            y: offset.y + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    static func inverseAspectFill(
        rect: CGRect,
        sourceSize: CGSize,
        destinationRect: CGRect
    ) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              destinationRect.width > 0,
              destinationRect.height > 0 else {
            return rect
        }

        let scale = max(
            destinationRect.width / sourceSize.width,
            destinationRect.height / sourceSize.height
        )
        let renderedSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let offset = CGPoint(
            x: destinationRect.minX + (destinationRect.width - renderedSize.width) / 2,
            y: destinationRect.minY + (destinationRect.height - renderedSize.height) / 2
        )

        return CGRect(
            x: (rect.minX - offset.x) / scale,
            y: (rect.minY - offset.y) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }
}
