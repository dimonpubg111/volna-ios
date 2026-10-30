import SwiftUI

@main
struct VOLNAApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var playback = PlaybackStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(playback)
                .preferredColorScheme(.dark).tint(VolnaStyle.coral)
        }
    }
}
