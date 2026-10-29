//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import AVFoundation
import AWSPredictionsPlugin

struct CameraView: UIViewControllerRepresentable {
    @ObservedObject var faceLivenessDetectionViewModel: FaceLivenessDetectionViewModel
    let presentationController: FaceLivenessPresentationController?

    init(
        faceLivenessDetectionViewModel: FaceLivenessDetectionViewModel,
        presentationController: FaceLivenessPresentationController? = nil
    ) {
        self.faceLivenessDetectionViewModel = faceLivenessDetectionViewModel
        self.presentationController = presentationController
    }

    func makeUIViewController(
        context: Context
    ) -> _LivenessViewController {
        let livenessViewController = _LivenessViewController(
            viewModel: faceLivenessDetectionViewModel,
            presentationController: presentationController
        )
        return livenessViewController
    }

    func updateUIViewController(
        _ uiViewController: _LivenessViewController,
        context: Context
    ) {}
}
