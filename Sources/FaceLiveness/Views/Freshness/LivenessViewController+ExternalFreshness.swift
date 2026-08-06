//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
@_spi(PredictionsFaceLiveness) import AWSPredictionsPlugin

extension _LivenessViewController {
    func displayExternalFreshness(
        colorSequences: [FaceLivenessSession.DisplayColor],
        controller: FaceLivenessExternalFreshnessController
    ) {
        ovalView?.setNeedsDisplay()
        freshnessView.isHidden = true
        viewModel.livenessState.displayingFreshness()

        controller.play(
            colorSequences,
            onAcknowledged: { [weak self] acknowledgedEvent in
                self?.viewModel.sendColorDisplayedEvent(acknowledgedEvent)
            },
            onComplete: { [weak self] in
                guard let self else { return }
                self.viewModel.handleFreshnessComplete()
            }
        )
    }
}
