import SwiftUI

enum MainTab: Hashable { case home, television, films, library }

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = MainTab.home
    @State private var film: Film?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView(onChannel: openChannel, onFilm: openFilm)
                    .safeAreaInset(edge: .bottom, spacing: 8) { miniPlayer }
            }.tabItem { Label("Головна", systemImage: "house") }.tag(MainTab.home)
            NavigationStack { TelevisionView() }
                .tabItem { Label("ТБ", systemImage: "tv") }.tag(MainTab.television)
            NavigationStack {
                FilmLibraryView(onFilm: openFilm).safeAreaInset(edge: .bottom, spacing: 8) { miniPlayer }
            }.tabItem { Label("Фільми", systemImage: "film") }.tag(MainTab.films)
            NavigationStack {
                MyLibraryView(onChannel: openChannel, onFilm: openFilm).safeAreaInset(edge: .bottom, spacing: 8) { miniPlayer }
            }.tabItem { Label("Моє", systemImage: "heart") }.tag(MainTab.library)
        }
        .sheet(item: $film) { FilmDetailView(film: $0) }
        .task { await library.refreshCatalogue(); await library.refreshSummary(force: true) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await library.refreshVisible()
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { break }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: playback.active)
    }
    @ViewBuilder private var miniPlayer: some View {
        if playback.active {
            HStack(spacing: 12) {
                Button {
                    if let id = playback.channelID {
                        library.channelID = id; tab = .television
                    } else if let id = playback.filmID { film = library.films.first { $0.id == id } }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: playback.isLive ? "waveform" : "play.rectangle.fill").font(.title3).foregroundStyle(VolnaStyle.coral)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playback.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(playback.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Відкрити плеєр: " + playback.title)
                Button { playback.toggle() } label: { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(playback.isPlaying ? "Пауза" : "Відтворити")
                Button { playback.stop() } label: { Image(systemName: "xmark").frame(width: 36, height: 44) }.accessibilityLabel("Закрити плеєр")
            }.padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 7).volnaGlass(24).padding(.horizontal, 14)
        }
    }
    private func openChannel(_ channel: Channel) {
        library.select(channel); playback.play(channel: channel, programme: library.now(for: channel)); tab = .television
    }
    private func openFilm(_ value: Film) { film = value }
}

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    let onChannel: (Channel) -> Void
    let onFilm: (Film) -> Void
    private var featured: Channel? { library.channels.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Твій вечір.\nТвоя хвиля.").font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("Улюблене завжди поруч").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 10)
                if let featured { hero(featured) }
                HStack(spacing: 12) {
                    fact("tv", value: "\(library.channels.count)", label: "каналів у плеєрі")
                    fact("airplayvideo", value: "AirPlay", label: "на великий екран")
                }
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("Зараз в ефірі", subtitle: "Те, що люблять дивитися")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) { ForEach(library.channels.prefix(12)) { channel in
                            Button { onChannel(channel) } label: {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack { ChannelLogo(channel: channel); Spacer(); LivePill() }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(channel.title).font(.headline).lineLimit(1)
                                        Text(library.now(for: channel)?.title ?? "Прямий ефір").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }.padding(18).frame(width: 240, alignment: .leading).volnaGlass()
                            }.buttonStyle(.plain)
                        } }
                    }.contentMargins(.trailing, 2)
                }
                if !library.films.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Кіно під настрій", subtitle: "Відкрий історію, яка зачепить")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(library.films.prefix(8)) { film in FilmCard(film: film, width: 140) { onFilm(film) } }
                            }
                        }
                    }
                }
                if library.catalogueOffline {
                    Label("Показуємо збережений каталог. Для перегляду потрібен інтернет.", systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }.background { CinemaBackdrop() }.toolbar { ToolbarItem(placement: .topBarLeading) { BrandMark() } }
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await library.refreshCatalogue(); await library.refreshSummary(force: true) }
    }
    private func hero(_ channel: Channel) -> some View {
        Button { onChannel(channel) } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hex: channel.color).opacity(0.55), Color.indigo.opacity(0.5), VolnaStyle.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let programme = library.now(for: channel), let image = programme.imageURL {
                    AsyncImage(url: image) { picture in picture.resizable().scaledToFill() } placeholder: { Color.clear }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 16) {
                    HStack { LivePill(text: "ТВІЙ ПРЯМИЙ ЕФІР"); Spacer(); Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.6)) }
                    Spacer(minLength: 40)
                    Text(library.now(for: channel)?.title ?? "Залишайся на своїй хвилі")
                        .font(.system(.title, design: .rounded).weight(.bold)).multilineTextAlignment(.leading).lineLimit(3)
                    HStack {
                        Label("Дивитися", systemImage: "play.fill").font(.subheadline.weight(.bold)).padding(.horizontal, 18).padding(.vertical, 12).background(VolnaStyle.coral, in: Capsule())
                        Spacer(); Text(channel.title).font(.caption.weight(.semibold)).padding(10).volnaGlass(16)
                    }
                }.padding(22)
            }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 32))
                .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.15), lineWidth: 0.7))
        }.buttonStyle(.plain).accessibilityLabel("Дивитися " + channel.title)
    }
    private func fact(_ symbol: String, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(VolnaStyle.rose)
            VStack(alignment: .leading, spacing: 3) { Text(value).font(.subheadline.bold()); Text(label).font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).volnaGlass(22)
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.title3.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
    }
}

#Preview("Головна") { RootView().environmentObject(LibraryStore()).environmentObject(PlaybackStore()).preferredColorScheme(.dark) }
