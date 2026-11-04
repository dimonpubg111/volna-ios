import SwiftUI

@main
struct VOLNAApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var playback = PlaybackStore()
    var body: some Scene {
        WindowGroup {
            WinterLaunchContainer().environmentObject(library).environmentObject(playback)
                .preferredColorScheme(.dark).tint(VolnaStyle.coral)
        }
    }
}

struct WinterLaunchContainer: View {
    @AppStorage("winter.motion") private var motion = true
    @AppStorage("winter.lightInterface") private var lightInterface = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showing = UserDefaults.standard.object(forKey: "winter.intro") as? Bool != false && !ProcessInfo.processInfo.arguments.contains("--ui-testing")
    var body: some View {
        ZStack {
            RootView().allowsHitTesting(!showing).accessibilityHidden(showing)
            if showing { WinterLaunchView().transition(.opacity).zIndex(10) }
        }
        .task {
            guard showing else { return }
            do { try await Task.sleep(nanoseconds: reduceMotion || !motion || lightInterface ? 1_100_000_000 : 2_300_000_000) } catch { return }
            withAnimation(.easeOut(duration: reduceMotion || !motion || lightInterface ? 0.12 : 0.48)) { showing = false }
        }
    }
}

struct WinterLaunchView: View {
    @AppStorage("winter.decorations") private var decorations = true
    @AppStorage("winter.motion") private var motion = true
    @AppStorage("winter.lightInterface") private var lightInterface = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var animated: Bool { motion && !lightInterface && !reduceMotion }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.03, green: 0.055, blue: 0.105).ignoresSafeArea()
                RadialGradient(colors: [Color(red: 0.15, green: 0.27, blue: 0.32), .clear], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: geometry.size.height * 0.65).ignoresSafeArea()
                if decorations {
                    VStack { Spacer(); WinterLandscape().frame(height: geometry.size.height * 0.27).opacity(0.38) }.ignoresSafeArea()
                }
                WinterSnow().allowsHitTesting(false)
                VStack(spacing: 0) {
                    Image(decorations ? "WinterLogo" : "WinterLogoPlain").resizable().scaledToFit().frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 31)).overlay(RoundedRectangle(cornerRadius: 31).stroke(.white.opacity(0.2), lineWidth: 0.7)).padding(.bottom, 30)
                    HStack(spacing: 5) {
                        ForEach(Array("VOLNA".enumerated()), id: \.offset) { index, letter in
                            Text(String(letter)).font(.system(size: 46, weight: .bold)).tracking(3)
                                .opacity(appeared || !animated ? 1 : 0).offset(y: appeared || !animated ? 0 : 9)
                                .animation(animated ? .easeOut(duration: 0.7).delay(0.15 + Double(index) * 0.075) : nil, value: appeared)
                        }
                    }.accessibilityLabel("VOLNA")
                    Text("На твоїй зимовій хвилі").font(.system(size: 11)).tracking(1.5).foregroundStyle(Color(red: 0.7, green: 0.8, blue: 0.85)).padding(.top, 13)
                }
                .offset(y: -25).scaleEffect(appeared || !animated ? 1 : 0.94)
                .opacity(appeared || !animated ? 1 : 0)
                .animation(animated ? .easeOut(duration: 0.85) : nil, value: appeared)
                VStack { Spacer(); Text("✦").font(.system(size: 16)).foregroundStyle(Color(red: 0.87, green: 0.78, blue: 0.62)); Text("ЗИМА 2026 / 2027").font(.system(size: 9)).tracking(3).foregroundStyle(.white.opacity(0.6)) }.padding(.bottom, 40)
            }.foregroundStyle(.white)
        }.onAppear { appeared = true }.accessibilityElement(children: .ignore).accessibilityLabel("Відкриваємо VOLNA")
    }
}
