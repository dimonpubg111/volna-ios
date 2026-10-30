import SwiftUI

enum VolnaStyle {
    static let coral = Color(red: 1, green: 0.24, blue: 0.35)
    static let rose = Color(red: 1, green: 0.53, blue: 0.62)
    static let background = Color(red: 0.027, green: 0.028, blue: 0.047)
    static let ink = Color(red: 0.07, green: 0.075, blue: 0.11)
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat = 24
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(VolnaStyle.ink, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.18), lineWidth: 0.7))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
        }
    }
}
extension View {
    func volnaGlass(_ radius: CGFloat = 24) -> some View { modifier(GlassSurface(radius: radius)) }
    // Scrolling content uses a static sheen. Live Liquid Glass remains on controls.
    func volnaCard(_ radius: CGFloat = 24) -> some View {
        background(LinearGradient(colors: [Color(red: 0.14, green: 0.13, blue: 0.18), VolnaStyle.ink], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
    }
}

struct GlassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.87 : 1)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct CinemaBackdrop: View {
    var body: some View {
        ZStack {
            VolnaStyle.background
            RadialGradient(colors: [VolnaStyle.coral.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.indigo.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 500)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path").font(.system(size: 25, weight: .bold)).foregroundStyle(VolnaStyle.coral)
            Text("VOLNA").font(.system(.headline, design: .rounded).weight(.black)).tracking(3)
        }.accessibilityElement(children: .combine)
    }
}
struct ChannelLogo: View {
    let channel: Channel
    var size: CGFloat = 48
    var body: some View {
        Text(channel.logoText ?? String(channel.title.prefix(2)))
            .font(.system(size: size * 0.37, weight: .black, design: .rounded))
            .minimumScaleFactor(0.5).lineLimit(1).padding(6)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hex: channel.color).opacity(0.9), Color(hex: channel.color).opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.3))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3).stroke(.white.opacity(0.15), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
extension Color {
    init(hex: String?) {
        let raw = (hex ?? "ff3d59").replacingOccurrences(of: "#", with: "")
        let number = UInt64(raw, radix: 16) ?? 0xff3d59
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}
struct LivePill: View {
    var text = "НАЖИВО"
    var body: some View {
        HStack(spacing: 5) { Circle().fill(VolnaStyle.coral).frame(width: 5, height: 5); Text(text).font(.system(size: 10, weight: .bold)).tracking(1) }
            .padding(.horizontal, 10).padding(.vertical, 7).background(.black.opacity(0.45), in: Capsule())
    }
}
struct GlassIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44).contentShape(Circle()) }
            .buttonStyle(.plain).volnaGlass(22).accessibilityLabel(label)
    }
}
struct EmptyMessage: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(VolnaStyle.rose)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(28).volnaCard()
    }
}
struct SearchField: View {
    @Binding var text: String
    var prompt = "Знайти свою хвилю"
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(prompt).focused($focused).submitLabel(.search).onSubmit { focused = false }
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Очистити пошук") }
        }.padding(.horizontal, 16).frame(minHeight: 48).volnaGlass(18)
    }
}
struct PosterArt: View {
    let film: Film
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.indigo.opacity(0.6), VolnaStyle.coral.opacity(0.25), VolnaStyle.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "film.stack").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.white.opacity(0.35))
            RemoteArtwork(url: film.posterURL)
        }.clipped().accessibilityHidden(true)
    }
}
