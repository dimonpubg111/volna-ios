import SwiftUI

struct TelevisionView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @State private var panel = 0
    @State private var query = ""
    @State private var category = "Усі"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filtered: [Channel] {
        library.channels.filter {
            (query.isEmpty || $0.title.matchesSearch(query)) &&
            (category == "Усі" || $0.category == category) &&
            (!library.favoritesOnly || library.favorites.contains($0.id))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            PlayerStage(placeholderChannel: library.selectedChannel)
                .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: 900)
            if let channel = library.selectedChannel {
                channelCaption(channel)
            }
            Picker("Вміст", selection: $panel) {
                Text("Канали").tag(0); Text("Телепрограма").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 14)
            if panel == 0 { channelBrowser } else { ProgrammeGuideView() }
        }
        .frame(maxWidth: .infinity).background { CinemaBackdrop() }
        .navigationTitle("Телебачення").navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: panel)
        .sensoryFeedback(.selection, trigger: library.channelID)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.favoritesOnly.toggle()
                } label: { Image(systemName: library.favoritesOnly ? "heart.fill" : "heart") }
                .accessibilityLabel(library.favoritesOnly ? "Усі канали" : "Обрані канали")
            }
        }
        .task(id: library.guideKey) {
            await library.refreshSelectedGuide()
            if let id = library.channelID { await library.refreshArchive(channelID: id) }
        }
    }
    private func channelCaption(_ channel: Channel) -> some View {
        HStack(spacing: 10) {
            ChannelLogo(channel: channel, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.title).font(.subheadline.weight(.bold)).lineLimit(1)
                Text(playback.recordingID != nil && playback.channelID == channel.id ? playback.title : library.now(for: channel)?.title ?? "Прямий ефір")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if playback.recordingID != nil || playback.channelID != channel.id {
                Button("До ефіру") { playback.play(channel: channel, programme: library.now(for: channel)) }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
            Button { library.toggleFavorite(channel.id) } label: {
                Image(systemName: library.favorites.contains(channel.id) ? "heart.fill" : "heart").frame(width: 40, height: 44)
            }.accessibilityLabel(library.favorites.contains(channel.id) ? "Прибрати з обраного" : "Додати в обране")
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
    private var channelBrowser: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                SearchField(text: $query, prompt: "Пошук каналу")
                Menu {
                    Button("Усі") { category = "Усі" }
                    ForEach(library.categories, id: \.self) { value in Button(value) { category = value } }
                } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 48, height: 48).volnaGlass(18) }
                .accessibilityLabel("Жанри каналів")
            }.padding(.horizontal, 16)
            if category != "Усі" {
                HStack { Text(category).font(.caption).foregroundStyle(.secondary); Button("Скинути") { category = "Усі" }; Spacer() }.font(.caption).padding(.horizontal, 20)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    if filtered.isEmpty {
                        EmptyMessage(symbol: "magnifyingglass", title: "Нічого не знайдено", message: "Спробуйте іншу назву або змініть жанр.").padding(16)
                    }
                    ForEach(filtered) { channel in
                        ChannelRow(channel: channel, selected: library.channelID == channel.id) {
                            library.select(channel)
                            playback.play(channel: channel, programme: library.now(for: channel))
                        }
                    }
                }.padding(.horizontal, 10).padding(.bottom, 16)
            }.scrollDismissesKeyboard(.interactively)
        }
    }
}

struct ChannelRow: View {
    @EnvironmentObject private var library: LibraryStore
    let channel: Channel
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ChannelLogo(channel: channel)
                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.title).font(.subheadline.weight(.semibold)).foregroundStyle(selected ? VolnaStyle.rose : .white)
                    Text(library.now(for: channel)?.title ?? "Прямий ефір").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let programme = library.now(for: channel) {
                        ProgressView(value: programme.progress(at: Date())).tint(VolnaStyle.coral).frame(maxWidth: 170)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "waveform" : "play.circle").foregroundStyle(selected ? VolnaStyle.coral : .white.opacity(0.35))
            }.padding(.horizontal, 14).padding(.vertical, 12)
                .background(selected ? VolnaStyle.coral.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Дивитися " + channel.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PlayerStage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    var placeholderChannel: Channel?
    var film: Film?
    @State private var settings = false
    private var displaysActive: Bool {
        if let film { return playback.filmID == film.id }
        return playback.channelID == placeholderChannel?.id && playback.filmID == nil
    }
    var body: some View {
        ZStack {
            Color.black
            if displaysActive && playback.hasVideo {
                NativePlayer(player: playback.player)
                if playback.loading {
                    ProgressView().tint(.white).padding(16).background(.black.opacity(0.55), in: Circle()).allowsHitTesting(false)
                }
                if let error = playback.error {
                    VStack(spacing: 12) {
                        Text(error).font(.caption).multilineTextAlignment(.center).lineLimit(3)
                        Button("Повторити") { playback.retry() }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.8))
                }
            } else {
                LinearGradient(colors: [VolnaStyle.coral.opacity(0.18), Color.indigo.opacity(0.2), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 12) {
                    Button {
                        if let film { playback.play(film: film) }
                        else if let channel = placeholderChannel { playback.play(channel: channel, programme: library.now(for: channel)) }
                    } label: { Image(systemName: "play.fill").font(.system(size: 25)).frame(width: 68, height: 68).volnaGlass(34) }
                        .buttonStyle(.plain).accessibilityLabel("Увімкнути відео")
                        .disabled(film != nil && film?.nativeSource == nil)
                    Text(film?.title ?? placeholderChannel?.title ?? "Оберіть канал").font(.subheadline.weight(.medium))
                }
            }
        }.overlay(alignment: .topTrailing) {
            if displaysActive && playback.hasVideo {
                HStack(spacing: 8) {
                    AirPlayRouteButton().frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle())
                    Button { settings = true } label: { Image(systemName: "gearshape").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle()) }
                        .buttonStyle(.plain).accessibilityLabel("Налаштування відео")
                }.padding(10)
            }
        }.overlay(alignment: .bottom) {
            if displaysActive && playback.slowConnection && playback.error == nil {
                Button("Довге завантаження · Повторити") { playback.retry() }
                    .font(.caption).padding(10).background(.black.opacity(0.8), in: Capsule()).padding(12)
            }
        }.sheet(isPresented: $settings) { PlaybackSettings() }
    }
}

struct ProgrammeGuideView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    private var programmes: [Programme] { library.selectedGuide?.programmes ?? [] }
    private var extras: [Recording] {
        guard let id = library.channelID else { return [] }
        return library.archiveForDay(channelID: id, key: KyivClock.key(KyivClock.day(library.dayOffset)))
            .filter { row in !programmes.contains { row.overlaps($0) } }
    }
    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(-2...1, id: \.self) { offset in
                        Button { library.dayOffset = offset } label: {
                            Text(offset == 1 ? "Завтра" : KyivClock.dayLabel(offset))
                                .font(.subheadline.weight(library.dayOffset == offset ? .bold : .regular))
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .background(library.dayOffset == offset ? VolnaStyle.coral.opacity(0.22) : .white.opacity(0.04), in: Capsule())
                                .overlay(Capsule().stroke(library.dayOffset == offset ? VolnaStyle.coral : .white.opacity(0.12), lineWidth: 0.7))
                        }.buttonStyle(.plain).accessibilityAddTraits(library.dayOffset == offset ? .isSelected : [])
                    }
                }.padding(.horizontal, 16)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let id = library.channelID, library.archiveRecovering.contains(id) {
                        Label("З’єднання з архівом відновлюється. Збережений список залишається тут.", systemImage: "arrow.clockwise")
                            .font(.caption).foregroundStyle(.secondary).padding(12)
                    }
                    if programmes.isEmpty && extras.isEmpty {
                        EmptyMessage(symbol: "calendar", title: library.guideErrors.contains(library.guideKey) ? "Розклад тимчасово недоступний" : "Оновлюємо телепрограму", message: "Минулі передачі можна ввімкнути, коли їхній запис справді збережений. Майбутні ще не доступні.")
                            .padding(.horizontal, 16)
                    }
                    ForEach(programmes) { programme in programmeRow(programme) }
                    ForEach(extras) { recording in
                        Button {
                            if let channel = library.selectedChannel { playback.play(recording: recording, channel: channel) }
                        } label: {
                            HStack(spacing: 14) {
                                Text(KyivClock.time(recording.startDate)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 50)
                                VStack(alignment: .leading, spacing: 5) { Text(recording.title).font(.subheadline.weight(.medium)); Text(recording.label).font(.caption).foregroundStyle(VolnaStyle.rose) }
                                Spacer(); Image(systemName: "play.circle.fill").foregroundStyle(VolnaStyle.coral)
                            }.padding(16).volnaCard(18)
                        }.buttonStyle(.plain).padding(.horizontal, 16)
                    }
                    if !programmes.isEmpty {
                        Text("Час за Києвом · Записи до 48 годин, якщо доступні у джерелі.")
                            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(16)
                    }
                }.padding(.bottom, 20)
            }.refreshable {
                await library.refreshSelectedGuide()
                if let id = library.channelID { await library.refreshArchive(channelID: id, force: true) }
            }
        }
    }
    private func programmeRow(_ programme: Programme) -> some View {
        let now = Date(), current = programme.isCurrent(at: now)
        let saved = library.channelID.flatMap { library.saved(programme, channelID: $0) }
        let ended = (programme.endDate ?? .distantFuture) <= now
        let available = current || (ended && saved != nil)
        return Button {
            guard let channel = library.selectedChannel else { return }
            if current { playback.play(channel: channel, programme: programme) }
            else if ended, let saved { playback.play(recording: saved, channel: channel) }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 5) {
                    Text(KyivClock.time(programme.startDate)).font(.subheadline.monospacedDigit())
                    if current { Text("ЕФІР").font(.system(size: 9, weight: .bold)).foregroundStyle(VolnaStyle.coral) }
                }.frame(width: 48).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(programme.title).font(.subheadline.weight(.medium)).lineLimit(3).foregroundStyle(current ? VolnaStyle.rose : .white)
                    Text(current ? "Наживо" : ended ? saved?.label ?? "Без запису" : "Незабаром").font(.caption).foregroundStyle(.secondary)
                    if current { ProgressView(value: programme.progress(at: now)).tint(VolnaStyle.coral) }
                }
                Spacer(minLength: 0)
                Image(systemName: available ? "play.circle.fill" : "clock").foregroundStyle(available ? VolnaStyle.coral : .white.opacity(0.22))
            }.padding(16).background(current ? VolnaStyle.coral.opacity(0.1) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(!available).opacity(!ended && !current ? 0.55 : 1).padding(.horizontal, 16)
    }
}

#Preview("Телебачення") { NavigationStack { TelevisionView() }.environmentObject(LibraryStore()).environmentObject(PlaybackStore()).preferredColorScheme(.dark) }
