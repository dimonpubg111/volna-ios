import SwiftUI
import AVKit

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = UIColor(red: 1, green: 0.24, blue: 0.35, alpha: 1)
        view.accessibilityLabel = "AirPlay: обрати телевізор"
        view.accessibilityIdentifier = "airplay-route-picker"
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
