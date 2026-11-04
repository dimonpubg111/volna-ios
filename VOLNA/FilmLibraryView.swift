import SwiftUI

struct FilmCard: View {
    let film: Film
    var width: CGFloat?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                PosterArt(film: film).aspectRatio(2 / 3, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        Text(film.nativeSource != nil ? "ДИВИТИСЯ" : "КАТАЛОГ")
                            .font(.system(size: 8, weight: .bold)).tracking(1).padding(7)
                            .background(.black.opacity(0.7), in: Capsule()).padding(9)
                    }.clipShape(RoundedRectangle(cornerRadius: 22))
                Text(film.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text([film.year.map(String.init), film.genre].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: width, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(GlassPressStyle()).accessibilityLabel(film.title + (film.nativeSource == nil ? ", інформація про фільм" : ", доступний перегляд"))
    }
}

struct FilmLibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    let onFilm: (Film) -> Void
    @State private var query = ""
    @State private var availableOnly = false
    @State private var genre = "Усі"
    @AppStorage("winter.hideAdult") private var hideAdult = false
    private var genres: [String] { Array(Set(library.films.compactMap(\.genre))).sorted() }
    private var filtered: [Film] {
        library.films.filter { (!hideAdult || $0.matureContent != true) && (query.isEmpty || $0.matches(query)) && (!availableOnly || $0.nativeSource != nil) && (genre == "Усі" || $0.genre == genre) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Знайди свою історію").font(.system(.largeTitle, design: .rounded).bold())
                SearchField(text: $query, prompt: "Назва, жанр або рік")
                HStack {
                    Menu {
                        Button("Усі жанри") { genre = "Усі" }
                        ForEach(genres, id: \.self) { value in Button(value) { genre = value } }
                    } label: { Label(genre == "Усі" ? "Жанри" : genre, systemImage: "line.3.horizontal.decrease").font(.subheadline).padding(12).volnaGlass(18) }
                    Spacer()
                    Toggle("Доступні", isOn: $availableOnly).font(.subheadline).fixedSize()
                }
                Text("Позначка «Каталог» означає, що фільм поки недоступний у власному плеєрі.")
                    .font(.caption).foregroundStyle(.secondary)
                if filtered.isEmpty {
                    EmptyMessage(symbol: "film.stack", title: availableOnly ? "Прямі відеоджерела ще не підключені" : "Нічого не знайдено", message: availableOnly ? "Можна дивитися канали та доступні записи в телепрограмі. Нові фільми з’являться після підключення сумісного джерела." : "Спробуйте іншу назву або скиньте жанр.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], alignment: .leading, spacing: 24) {
                    ForEach(filtered) { film in FilmCard(film: film) { onFilm(film) } }
                }
            }.padding(20).padding(.bottom, 20)
        }.background { CinemaBackdrop() }.navigationTitle("Фільми").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
    }
}

struct FilmDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    let film: Film
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if film.nativeSource != nil {
                        PlayerStage(film: film).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 24))
                    } else {
                        PosterArt(film: film).aspectRatio(2 / 3, contentMode: .fit).frame(maxWidth: 230).clipShape(RoundedRectangle(cornerRadius: 28)).frame(maxWidth: .infinity)
                    }
                    Text(film.title).font(.system(.largeTitle, design: .rounded).bold())
                    Text([film.year.map(String.init), film.genre, film.duration].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if film.nativeSource != nil {
                        Button { playback.play(film: film) } label: { Label("Дивитися", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    } else {
                        Label("У власному плеєрі поки недоступний", systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).volnaGlass(20)
                    }
                    if let synopsis = film.synopsis { Text(synopsis).font(.body).foregroundStyle(.white.opacity(0.8)).lineSpacing(5) }
                    Button { library.toggleFavorite(film.id) } label: {
                        Label(library.favorites.contains(film.id) ? "В обраному" : "Зберегти в обране", systemImage: library.favorites.contains(film.id) ? "heart.fill" : "heart")
                            .frame(maxWidth: .infinity).padding(14).volnaGlass(22)
                    }.buttonStyle(.plain)
                }.padding(20)
            }.background { CinemaBackdrop() }.navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
}

struct MyLibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    let onChannel: (Channel) -> Void
    let onFilm: (Film) -> Void
    @State private var settings = false
    @AppStorage("winter.snow") private var snow = true
    @AppStorage("winter.decorations") private var decorations = true
    @AppStorage("winter.motion") private var motion = true
    @AppStorage("winter.intro") private var intro = true
    @AppStorage("winter.lightInterface") private var lightInterface = false
    @AppStorage("winter.compact") private var compact = false
    @AppStorage("winter.largeText") private var largeText = false
    @AppStorage("winter.hideAdult") private var hideAdult = false
    @AppStorage("winter.snowIntensity") private var snowIntensity = "light"
    private var channels: [Channel] { library.channels.filter { library.favorites.contains($0.id) } }
    private var films: [Film] { library.films.filter { library.favorites.contains($0.id) && (!hideAdult || $0.matureContent != true) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("VOLNA · ОСОБИСТИЙ ПРОСТІР").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(Color(red: 0.74, green: 0.87, blue: 0.93))
                    HStack(spacing: 14) {
                        Image(systemName: "snowflake").font(.title).foregroundStyle(.white).frame(width: 58, height: 64).volnaGlass(22)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Твоя зимова хвиля").font(.system(.title2, design: .rounded).bold())
                            Text("Трохи затишку. Усе улюблене поруч.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack { Text("Зима 2026 / 2027"); Spacer(); Image(systemName: "sparkle").foregroundStyle(Color(red: 0.93, green: 0.8, blue: 0.59)) }.font(.caption2)
                }.padding(22).volnaCard(28)
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("Зроби по-своєму").font(.headline); Spacer(); Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary) }
                    winterSetting("Легкий сніг", note: "Сніжинки на головній. Без снігу під час відео.", symbol: "snowflake", value: $snow)
                    Picker("Снігопад", selection: $snowIntensity) { Text("Легкий").tag("light"); Text("Помірний").tag("medium"); Text("Сніжний вечір").tag("full") }.font(.subheadline)
                    Divider().overlay(.white.opacity(0.06))
                    winterSetting("Святкові деталі", note: "Шапка на VOLNA та засніжений пейзаж.", symbol: "sparkles", value: $decorations)
                    Divider().overlay(.white.opacity(0.06))
                    winterSetting("М’яка анімація", note: "Вимкни, якщо хочеш менше руху.", symbol: "wind", value: $motion)
                    Divider().overlay(.white.opacity(0.06))
                    winterSetting("Зимова заставка", note: "Коротке привітання під час запуску застосунку.", symbol: "sparkle", value: $intro)
                    Divider().overlay(.white.opacity(0.06))
                    winterSetting("Легкий інтерфейс", note: "Без розмиття та рухомих ефектів.", symbol: "leaf", value: $lightInterface)
                    Divider().overlay(.white.opacity(0.06))
                    winterSetting("Компактні канали", note: "Більше каналів на одному екрані.", symbol: "list.bullet", value: $compact)
                    Divider().overlay(.white.opacity(0.06))
                    winterSetting("Крупніший текст", note: "Зручніше читати назви та налаштування.", symbol: "textformat.size", value: $largeText)
                    Divider().overlay(.white.opacity(0.06))
                    winterSetting("Без дорослих комедій", note: "Приховати «Свінгери» та інші дорослі добірки.", symbol: "heart", value: $hideAdult)
                    Text("Налаштування зберігаються на цьому iPhone.").font(.caption2).foregroundStyle(.secondary)
                }.padding(20).volnaCard(26)
                HStack { Text("Те, що любиш").font(.title3.bold()); Spacer(); Text("\(channels.count + films.count)").font(.caption).foregroundStyle(.secondary) }
                if channels.isEmpty && films.isEmpty {
                    EmptyMessage(symbol: "heart", title: "Улюблене буде тут", message: "Натисни сердечко біля каналу або фільму. Обране зберігається на цьому пристрої.")
                }
                if !channels.isEmpty {
                    Text("Мої канали").font(.title3.bold())
                    LazyVStack(spacing: 4) { ForEach(channels) { channel in ChannelRow(channel: channel) { onChannel(channel) } } }
                }
                if !films.isEmpty {
                    Text("Моє кіно").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 20) {
                        ForEach(films) { film in FilmCard(film: film) { onFilm(film) } }
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label("Твій перегляд", systemImage: "play.rectangle").font(.headline)
                    Picker("Таймер сну", selection: Binding(get: { playback.sleepMinutes }, set: { playback.setSleepTimer(minutes: $0) })) { Text("Вимкнено").tag(0); Text("15 хв").tag(15); Text("30 хв").tag(30); Text("60 хв").tag(60) }.font(.subheadline)
                    if let end = playback.sleepEndsAt { Text("Відео стане на паузу о " + end.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                    Button { settings = true } label: { HStack { Label("Якість, звук і субтитри", systemImage: "slider.horizontal.3"); Spacer(); Image(systemName: "chevron.right") }.font(.subheadline) }
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text("AirPlay").font(.subheadline.weight(.semibold)); Text("Обери телевізор у своїй мережі").font(.caption2).foregroundStyle(.secondary) }
                        Spacer(); AirPlayRouteButton().frame(width: 44, height: 44)
                    }
                    Text("Обране зберігається на пристрої. Відео потребує інтернету.").font(.caption2).foregroundStyle(.secondary)
                }.padding(20).volnaCard()
            }.padding(20)
        }.background { CinemaBackdrop() }.navigationTitle("Налаштування").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $settings) { PlaybackSettings() }
    }
    private func winterSetting(_ title: String, note: String, symbol: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color(red: 0.76, green: 0.88, blue: 0.95)).frame(width: 34, height: 38).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.medium)); Text(note).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }.tint(VolnaStyle.coral)
    }
}
