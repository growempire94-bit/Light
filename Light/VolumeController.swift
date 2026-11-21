import MediaPlayer
import SwiftUI
import UIKit

/// iOS has no public API to change the system volume. The usual workaround is
/// a hidden MPVolumeView whose slider we move to 100 %. Best effort: if Apple
/// breaks it, the alarm still plays at the current volume.
final class VolumeController {
    static let shared = VolumeController()

    let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.0001
        view.isUserInteractionEnabled = false
        return view
    }()

    private init() {}

    func setMaxVolume() {
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        // The slider needs a moment after creation before it accepts values.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            slider.setValue(1.0, animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }
}

/// Puts the hidden MPVolumeView into the window hierarchy (required for it to work).
struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.isUserInteractionEnabled = false
        let volumeView = VolumeController.shared.volumeView
        volumeView.removeFromSuperview()
        container.addSubview(volumeView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
