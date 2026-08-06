//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import UIKit

class OvalView: UIView {
    struct Style {
        /// Fill applied everywhere outside the oval.
        var dimColor: UIColor
        var strokeColor: UIColor
        var lineWidth: CGFloat
        /// `[dash, gap]` lengths. Empty means a solid stroke.
        var dashPattern: [CGFloat]

        static let `default` = Style(
            dimColor: UIColor.black.withAlphaComponent(0.70),
            strokeColor: .hex("#7DB8FF"),
            lineWidth: 3,
            dashPattern: [3, 4]
        )
    }

    let ovalFrame: CGRect
    let style: Style

    init(frame: CGRect, ovalFrame: CGRect, style: Style = .default) {
        self.ovalFrame = ovalFrame
        self.style = style
        super.init(frame: frame)
        backgroundColor = .clear
    }

    override func draw(_ rect: CGRect) {
        let mask = UIBezierPath(rect: bounds)
        let oval = UIBezierPath(ovalIn: ovalFrame)
        mask.append(oval.reversing())

        style.dimColor.setFill()
        mask.fill()

        style.strokeColor.setStroke()
        oval.lineWidth = style.lineWidth
        oval.lineCapStyle = .round
        if !style.dashPattern.isEmpty {
            let dashes = style.dashPattern
            oval.setLineDash(dashes, count: dashes.count, phase: 0)
        }
        oval.stroke()
    }

    required init?(coder: NSCoder) { nil }
}

#if DEBUG
import SwiftUI

struct OvalView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(white: 0.35)
            PreviewOvalView()
        }
        .edgesIgnoringSafeArea(.all)
        .previewDisplayName("Oval")
    }
}
#endif
