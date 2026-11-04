import SwiftUI

enum VolnaStyle {
    static let coral = Color(red: 1, green: 0.24, blue: 0.35)
    static let rose = Color(red: 1, green: 0.53, blue: 0.62)
    static let background = Color(red: 0.027, green: 0.028, blue: 0.047)
    static let ink = Color(red: 0.07, green: 0.075, blue: 0.11)
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat = 24
    @AppStorage("winter.lightInterface") private var lightInterface = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || lightInterface {
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
    func volnaCard(_ radius: CGFloat = 28) -> some View {
        background(LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.23), VolnaStyle.ink], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: max(radius, 28), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: max(radius, 28), style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
    }
}

struct GlassPressStyle: ButtonStyle {
    @AppStorage("winter.motion") private var motion = true
    @AppStorage("winter.lightInterface") private var lightInterface = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.87 : 1)
            .scaleEffect(!reduceMotion && motion && !lightInterface && configuration.isPressed ? 0.975 : 1)
            .animation(reduceMotion || !motion || lightInterface ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct CinemaBackdrop: View {
    var body: some View {
        ZStack {
            VolnaStyle.background
            RadialGradient(colors: [Color(red: 0.17, green: 0.36, blue: 0.43).opacity(0.48), .clear], center: .topLeading, startRadius: 0, endRadius: 450)
            RadialGradient(colors: [Color.indigo.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 500)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}
struct BrandMark: View {
    @AppStorage("winter.decorations") private var decorations = true
    var body: some View {
        HStack(spacing: 8) {
            Image(decorations ? "WinterLogo" : "WinterLogoPlain").resizable().scaledToFit().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
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

struct WinterHat: View {
    var body: some View {
        Canvas { context, size in
            var hat = Path()
            hat.move(to: CGPoint(x: 2, y: size.height * 0.7))
            hat.addQuadCurve(to: CGPoint(x: size.width * 0.72, y: 3), control: CGPoint(x: 7, y: -3))
            hat.addQuadCurve(to: CGPoint(x: size.width - 2, y: 12), control: CGPoint(x: size.width, y: 1))
            hat.addLine(to: CGPoint(x: size.width * 0.6, y: size.height * 0.73))
            hat.closeSubpath()
            context.fill(hat, with: .color(VolnaStyle.coral))
            context.fill(Path(roundedRect: CGRect(x: 0, y: size.height * 0.68, width: size.width * 0.76, height: 5), cornerRadius: 2), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: size.width - 7, y: 9, width: 7, height: 7)), with: .color(.white))
        }
    }
}

struct WinterLandscape: View {
    @AppStorage("winter.decorations") private var decorations = true
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.18, green: 0.34, blue: 0.41), Color(red: 0.07, green: 0.12, blue: 0.21)], startPoint: .topTrailing, endPoint: .bottomLeading)
            if decorations {
                Canvas { context, size in
                    func polygon(_ points: [(CGFloat, CGFloat)], _ color: Color) {
                        var path = Path()
                        for (i, point) in points.enumerated() {
                            let p = CGPoint(x: point.0 * size.width, y: point.1 * size.height)
                            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                        path.closeSubpath(); context.fill(path, with: .color(color))
                    }
                    polygon([(0,0.8),(0.2,0.3),(0.4,0.7),(0.6,0.18),(1,0.9),(1,1),(0,1)], Color(red: 0.21, green: 0.34, blue: 0.43))
                    polygon([(0.6,0.18),(0.49,0.39),(0.57,0.34),(0.61,0.42),(0.65,0.31),(0.71,0.37)], .white.opacity(0.6))
                    for i in 0..<8 {
                        let x = CGFloat(i) * 0.15 - 0.04
                        let h: CGFloat = i % 2 == 0 ? 0.36 : 0.25
                        polygon([(x-0.08,0.9),(x,0.9-h),(x+0.08,0.9)], Color(red: 0.06, green: 0.2, blue: 0.19))
                        polygon([(x-0.025,0.9-h+0.07),(x,0.9-h),(x+0.025,0.9-h+0.07)], .white.opacity(0.75))
                    }
                    polygon([(0,0.92),(0.25,0.86),(0.54,0.95),(0.8,0.84),(1,0.9),(1,1),(0,1)], Color(red: 0.76, green: 0.86, blue: 0.9))
                    polygon([(0.73,0.88),(0.73,0.72),(0.82,0.62),(0.91,0.72),(0.91,0.88)], Color(red: 0.4, green: 0.2, blue: 0.24))
                    polygon([(0.71,0.73),(0.82,0.6),(0.93,0.73),(0.91,0.75),(0.82,0.65),(0.73,0.75)], .white.opacity(0.92))
                    for x in [CGFloat(0.76), CGFloat(0.84)] {
                        context.fill(Path(roundedRect: CGRect(x: x * size.width, y: size.height * 0.76, width: size.width * 0.04, height: size.height * 0.06), cornerRadius: 1), with: .color(Color(red: 1, green: 0.82, blue: 0.56)))
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}

// Only the small home hero animates, at 15 fps. No snow while video is active.
struct WinterSnow: View {
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("winter.snow") private var snow = true
    @AppStorage("winter.motion") private var motion = true
    @AppStorage("winter.lightInterface") private var lightInterface = false
    @AppStorage("winter.snowIntensity") private var snowIntensity = "light"
    var body: some View {
        if snow && motion && !lightInterface && !reduceMotion && !playback.active && scenePhase == .active {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120)
                    for i in 0..<(snowIntensity == "full" ? 24 : snowIntensity == "medium" ? 16 : 8) {
                        let x = CGFloat((i * 73 + 19) % 100) / 100 * size.width
                        let y = CGFloat((time * Double(7 + i % 4) + Double(i * 17)).truncatingRemainder(dividingBy: Double(max(1, size.height))))
                        let radius = CGFloat(1 + i % 2)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.5)))
                    }
                }
            }.accessibilityHidden(true)
        }
    }
}

struct WinterSnowEdge: View {
    @AppStorage("winter.decorations") private var decorations = true
    var body: some View {
        if decorations {
            Canvas { context, size in
                var path = Path()
                path.move(to: .zero); path.addLine(to: CGPoint(x: size.width, y: 0))
                for i in stride(from: 40, through: 0, by: -1) {
                    let x = CGFloat(i) / 40 * size.width
                    let y = size.height * (0.55 + CGFloat(sin(Double(i) * 1.7)) * 0.18)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.closeSubpath(); context.fill(path, with: .color(Color(red: 0.85, green: 0.93, blue: 0.97)))
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
