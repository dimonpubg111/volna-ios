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
    private var genres: [String] { Array(Set(library.films.compactMap(\.genre))).sorted() }
    private var filtered: [Film] {
        library.films.filter { (query.isEmpty || $0.matches(query)) && (!availableOnly || $0.nativeSource != nil) && (genre == "Усі" || $0.genre == genre) }
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
    private var channels: [Channel] { library.channels.filter { library.favorites.contains($0.id) } }
    private var films: [Film] { library.films.filter { library.favorites.contains($0.id) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image(systemName: "heart.fill").font(.title2).foregroundStyle(VolnaStyle.rose).frame(width: 62, height: 62).volnaGlass(24)
                    VStack(alignment: .leading, spacing: 4) { Text("Твій простір").font(.title2.bold()); Text("Без реєстрації. З турботою про тебе.").font(.caption).foregroundStyle(.secondary) }
                }.padding(.top, 12)
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
                    Label("VOLNA для iPhone", systemImage: "iphone").font(.headline)
                    Text("Нативний інтерфейс, системне відтворення, AirPlay і «Картинка в картинці». Реклама, що вже міститься у відеопотоці, може залишатися.").font(.caption).foregroundStyle(.secondary)
                    Button { settings = true } label: { Label("Налаштування відтворення", systemImage: "gearshape").font(.subheadline) }
                    Text("Версія 2.1 · Обране зберігається локально. Відео не завантажується для офлайн-перегляду.").font(.caption2).foregroundStyle(.secondary)
                }.padding(20).volnaCard()
            }.padding(20)
        }.background { CinemaBackdrop() }.navigationTitle("Моє").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $settings) { PlaybackSettings() }
    }
}
