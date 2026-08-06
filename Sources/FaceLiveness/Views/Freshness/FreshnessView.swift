//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import UIKit

final class FreshnessView: UIView {
    let oldRectangle = UIView()
    let fractionalRectangle = UIView()

    private let ovalPulseLayer = CAShapeLayer()
    private var ovalPulseFrame: CGRect?

    var fractionalRectangleBottom: NSLayoutConstraint?
    var oldRectangleTop: NSLayoutConstraint?

    func clearColors() {
        backgroundColor = .clear
        oldRectangle.backgroundColor = .clear
        fractionalRectangle.backgroundColor = .clear
    }

    func startOvalPulse(in ovalFrame: CGRect) {
        ovalPulseFrame = ovalFrame
        updateOvalPulsePath()

        ovalPulseLayer.fillColor = UIColor.clear.cgColor
        ovalPulseLayer.strokeColor = UIColor.white.cgColor
        ovalPulseLayer.lineWidth = 3
        ovalPulseLayer.lineCap = .round
        ovalPulseLayer.lineDashPattern = [3, 4]
        ovalPulseLayer.shadowColor = UIColor.white.cgColor
        ovalPulseLayer.shadowOpacity = 0.65
        ovalPulseLayer.shadowRadius = 8
        ovalPulseLayer.shadowOffset = .zero

        if ovalPulseLayer.superlayer == nil {
            layer.addSublayer(ovalPulseLayer)
        }

        ovalPulseLayer.removeAllAnimations()
        guard !UIAccessibility.isReduceMotionEnabled else {
            ovalPulseLayer.opacity = 1
            return
        }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.35
        opacity.toValue = 1

        let lineWidth = CABasicAnimation(keyPath: "lineWidth")
        lineWidth.fromValue = 2.5
        lineWidth.toValue = 4

        let pulse = CAAnimationGroup()
        pulse.animations = [opacity, lineWidth]
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ovalPulseLayer.add(pulse, forKey: "freshnessOvalPulse")
    }

    func stopOvalPulse() {
        ovalPulseLayer.removeAllAnimations()
        ovalPulseLayer.removeFromSuperlayer()
        ovalPulseFrame = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOvalPulsePath()
    }

    private func updateOvalPulsePath() {
        guard let ovalPulseFrame else { return }
        ovalPulseLayer.frame = bounds
        ovalPulseLayer.path = UIBezierPath(ovalIn: ovalPulseFrame).cgPath
    }

    init() {
        super.init(frame: .zero)
        oldRectangle.translatesAutoresizingMaskIntoConstraints = false
        fractionalRectangle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(oldRectangle)
        addSubview(fractionalRectangle)

        fractionalRectangleBottom = fractionalRectangle.bottomAnchor.constraint(equalTo: topAnchor)
        oldRectangleTop = oldRectangle.topAnchor.constraint(equalTo: topAnchor)

        fractionalRectangleBottom?.isActive = true
        oldRectangleTop?.isActive = true

        NSLayoutConstraint.activate([
            oldRectangle.leadingAnchor.constraint(equalTo: leadingAnchor),
            oldRectangle.bottomAnchor.constraint(equalTo: bottomAnchor),
            oldRectangle.trailingAnchor.constraint(equalTo: trailingAnchor),

            fractionalRectangle.topAnchor.constraint(equalTo: topAnchor),
            fractionalRectangle.leadingAnchor.constraint(equalTo: leadingAnchor),
            fractionalRectangle.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
}
