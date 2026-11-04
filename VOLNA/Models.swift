import Foundation

enum VolnaConfiguration {
    static let origin = URL(string: "https://volna-cinema-tv.spunkyhaven129.chatgpt.site")!
    static let retention: TimeInterval = 48 * 60 * 60
    static func api(_ path: String, query: [URLQueryItem] = []) -> URL {
        var c = URLComponents(url: origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = query.isEmpty ? nil : query
        return c.url!
    }
    static func mediaURL(_ value: String?) -> URL? {
        guard let value, value.count <= 8192,
              let url = URL(string: value, relativeTo: origin)?.absoluteURL,
              url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty,
              host != "localhost", !host.hasSuffix(".local"),
              !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }),
              url.port == nil || url.port == 443 else { return nil }
        return url
    }
    static func archiveURL(id: String) -> URL? {
        guard (1...160).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return api("api/archive/\(id)/index.m3u8")
    }
}

struct MediaSource: Codable, Hashable, Sendable {
    let type: String
    let url: String?
    let language: String?
    let label: String?
    let publicMovieId: String?
    var nativeURL: URL? {
        guard ["hls", "video", "mp4"].contains(type), publicMovieId == nil else { return nil }
        return VolnaConfiguration.mediaURL(url)
    }
}

struct Channel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let logoText: String?
    let color: String?
    let category: String?
    let country: String?
    let sources: [MediaSource]
    var nativeSource: MediaSource? { sources.first { $0.nativeURL != nil } }
}

struct Film: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let type: String?
    let year: Int?
    let genre: String?
    let duration: String?
    let poster: String?
    let synopsis: String?
    let searchAliases: [String]?
    let sources: [MediaSource]
    let playbackAvailable: Bool?
    let availabilityNote: String?
    let matureContent: Bool?
    var nativeSource: MediaSource? {
        // These two broadcaster-public films are resolved afresh from this device.
        if let source = sources.first(where: { $0.type == "hls" && $0.publicMovieId == id && OfficialFilmResolver.supports(id) }) { return source }
        guard playbackAvailable != false else { return nil }
        return sources.first { $0.nativeURL != nil }
    }
    var posterURL: URL? { VolnaConfiguration.mediaURL(poster) }
    func matches(_ query: String) -> Bool {
        ([title, genre ?? "", year.map(String.init) ?? ""] + (searchAliases ?? [])).joined(separator: " ").matchesSearch(query)
    }
}

enum OfficialFilmResolver {
    private struct Expected { let video: String; let minimum: Int; let maximum: Int }
    private static let movies = ["rasha-hudbai": Expected(video: "hu7B3j1R", minimum: 5900, maximum: 6200), "black-raven": Expected(video: "DtPGoifu", minimum: 6500, maximum: 6700), "svingery": Expected(video: "cuh7frgR", minimum: 5520, maximum: 5550), "svingery-2": Expected(video: "fCQ6y5La", minimum: 5130, maximum: 5160), "ya-s-toboj": Expected(video: "7tzK4FaJ", minimum: 5160, maximum: 5190), "bitva-za-kiyiv": Expected(video: "L28nB9f2", minimum: 3200, maximum: 3230), "chat-vijni-moshtun": Expected(video: "NCkKIddR", minimum: 2930, maximum: 2960)]
    private struct Configuration: Decodable { let id: String; let duration: Int; let live: Bool; let dl: Int; let bpas: Int; let balancer: String }
    static func supports(_ id: String) -> Bool { movies[id] != nil }
    static func resolve(_ id: String) async throws -> URL {
        guard let expected = movies[id], let embed = URL(string: "https://1plus1.video/video/embed/" + expected.video) else { throw LibraryFailure.invalid }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: OfficialFilmRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let html = try await text(embed, limit: 128_000, session: session)
        let regex = try NSRegularExpression(pattern: #"new OVVA\(\s*"ovva-player"\s*,\s*"([A-Za-z0-9+/=]{1,90000})""#)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html), let data = Data(base64Encoded: String(html[range])) else { throw LibraryFailure.invalid }
        let c = try JSONDecoder().decode(Configuration.self, from: data)
        guard c.id == expected.video, !c.live, c.dl == -1, c.bpas == -1, (expected.minimum...expected.maximum).contains(c.duration),
              let balancer = URL(string: c.balancer), balancer.scheme == "https", balancer.host == "grandcentral.1plus1.video", balancer.path.hasPrefix("/vod/"), balancer.user == nil, balancer.password == nil, balancer.port == nil, balancer.query == nil, balancer.fragment == nil else { throw LibraryFailure.invalid }
        let reply = try await text(balancer, limit: 4096, session: session).trimmingCharacters(in: .whitespacesAndNewlines)
        guard reply.hasPrefix("302="), let media = URL(string: String(reply.dropFirst(4))), media.scheme == "https", media.port == nil,
              let host = media.host, host.range(of: #"^vod-k\d{4}-kbp\.1plus1\.video$"#, options: .regularExpression) != nil,
              media.user == nil, media.password == nil, media.query == nil, media.fragment == nil,
              media.path.range(of: #"^/vod/\d{10}/[A-Za-z0-9_-]+/\d{6}/[a-f0-9/]+\.smil/playlist\.m3u8$"#, options: .regularExpression) != nil,
              let expires = TimeInterval(media.path.split(separator: "/")[1]), expires > Date().timeIntervalSince1970 + 60 else { throw LibraryFailure.invalid }
        try Task.checkCancellation(); return media
    }
    private static func text(_ url: URL, limit: Int, session: URLSession) async throws -> String {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.expectedContentLength <= Int64(limit) else { throw LibraryFailure.unavailable }
        var data = Data()
        for try await byte in bytes { if data.count >= limit { throw LibraryFailure.oversized }; if data.count % 4096 == 0 { try Task.checkCancellation() }; data.append(byte) }
        guard let value = String(data: data, encoding: .utf8) else { throw LibraryFailure.invalid }; return value
    }
}
private final class OfficialFilmRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct Catalogue: Codable, Sendable {
    let channels: [Channel]
    let movies: [Film]
    var ukrainianChannels: [Channel] {
        let priorities = ["novyi", "tet", "stb", "1plus1Ukraina", "ictv2", "bigudi", "2plus2"]
        return channels.enumerated().filter { $0.element.country == "UA" && $0.element.nativeSource != nil }
            .sorted {
                let a = priorities.firstIndex(of: $0.element.id) ?? 999
                let b = priorities.firstIndex(of: $1.element.id) ?? 999
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
    }
}

// Construct once per catalogue update, rather than sorting during each row render.
struct ChannelIndex: Sendable {
    let channels: [Channel]
    let byID: [String: Channel]
    let categories: [String]
    init(catalogue: Catalogue?) {
        channels = catalogue?.ukrainianChannels ?? []
        byID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        categories = Array(Set(channels.compactMap(\.category))).sorted()
    }
}

struct Programme: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: String
    let end: String
    let description: String?
    let image: String?
    var startDate: Date? { KyivClock.parse(start) }
    var endDate: Date? { KyivClock.parse(end) }
    func isCurrent(at now: Date) -> Bool {
        guard let startDate, let endDate else { return false }
        return startDate <= now && now < endDate
    }
    var imageURL: URL? { VolnaConfiguration.mediaURL(image) }
    func progress(at now: Date) -> Double {
        guard let startDate, let endDate, endDate > startDate else { return 0 }
        return min(1, max(0, now.timeIntervalSince(startDate) / endDate.timeIntervalSince(startDate)))
    }
}

struct GuideSummary: Codable, Sendable {
    struct Entry: Codable, Sendable, Equatable { let now: Programme?; let next: Programme? }
    let status: String
    let channels: [String: Entry]
}
struct GuideDay: Codable, Sendable, Equatable {
    let status: String
    let programmes: [Programme]
    let availableDates: [String]?
}
struct Recording: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let channelId: String
    let title: String
    let start: String
    let end: String
    let status: String
    let playable: Bool
    let coveredSeconds: Double?
    let durationSeconds: Double?
    let playbackStartOffsetSeconds: Double?
    let playbackEndSeconds: Double?
    let coverageRatio: Double?
    let fullProgramme: Bool?
    var startDate: Date? { KyivClock.parse(start) }
    var endDate: Date? { KyivClock.parse(end) }
    var offset: Double { playbackStartOffsetSeconds ?? 0 }
    var playbackLimit: Double { playbackEndSeconds ?? (offset + (coveredSeconds ?? durationSeconds ?? 0)) }
    var nativeURL: URL? { VolnaConfiguration.archiveURL(id: id) }
    func isPlayable(at now: Date) -> Bool {
        guard playable, ["novyi", "tet"].contains(channelId), let startDate, let endDate,
              startDate < now, endDate > startDate, endDate > now.addingTimeInterval(-VolnaConfiguration.retention),
              !["future", "expired"].contains(status), nativeURL != nil,
              offset.isFinite, playbackLimit.isFinite, offset >= 0, playbackLimit > offset, playbackLimit <= 172800 else { return false }
        return (coveredSeconds ?? durationSeconds ?? 0) > 0
    }
    func overlaps(_ programme: Programme) -> Bool {
        guard let a = startDate, let b = endDate, let c = programme.startDate, let d = programme.endDate else { return false }
        let overlap = min(b, d).timeIntervalSince(max(a, c))
        return overlap > 0 && (abs(a.timeIntervalSince(c)) < 120 || overlap / max(1, d.timeIntervalSince(c)) >= 0.75)
    }
    var label: String { fullProgramme == true && status == "ready" ? "Запис" : status == "recording" ? "Записується" : "Фрагмент" }
}
struct ArchiveCatalogue: Codable, Sendable {
    struct State: Codable, Sendable { let archiveRecovering: Bool?; let recordingActive: Bool? }
    let recordings: [Recording]
    let state: State?
}

// Formatters are expensive. Access is serialized because API decoding and UI work
// can run on different executors; the bounded cache holds no video or user data.
private final class KyivDateCache: @unchecked Sendable {
    private let lock = NSLock()
    private let dates = NSCache<NSString, NSDate>()
    private let fractional = ISO8601DateFormatter()
    private let plain = ISO8601DateFormatter()
    private let dayKey = DateFormatter()
    private let clock = DateFormatter()
    private let dayTitle = DateFormatter()
    init() {
        dates.countLimit = 4096
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for formatter in [dayKey, clock, dayTitle] {
            formatter.calendar = KyivClock.calendar
            formatter.timeZone = KyivClock.calendar.timeZone
            formatter.locale = Locale(identifier: "uk_UA")
        }
        dayKey.locale = Locale(identifier: "en_US_POSIX")
        dayKey.dateFormat = "yyyy-MM-dd"; clock.dateFormat = "HH:mm"; dayTitle.dateFormat = "d MMM"
    }
    func parse(_ value: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        if let cached = dates.object(forKey: value as NSString) { return cached as Date }
        guard let date = fractional.date(from: value) ?? plain.date(from: value) else { return nil }
        dates.setObject(date as NSDate, forKey: value as NSString)
        return date
    }
    func key(_ date: Date) -> String { lock.lock(); defer { lock.unlock() }; return dayKey.string(from: date) }
    func time(_ date: Date) -> String { lock.lock(); defer { lock.unlock() }; return clock.string(from: date) }
    func title(_ date: Date) -> String { lock.lock(); defer { lock.unlock() }; return dayTitle.string(from: date) }
}

enum KyivClock {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return c
    }()
    private static let cache = KyivDateCache()
    static func parse(_ value: String) -> Date? {
        cache.parse(value)
    }
    static func key(_ date: Date = Date()) -> String {
        cache.key(date)
    }
    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return cache.time(date)
    }
    static func day(_ offset: Int, from now: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }
    static func dayLabel(_ offset: Int) -> String {
        if offset == 0 { return "Сьогодні" }; if offset == -1 { return "Вчора" }; if offset == -2 { return "Позавчора" }
        return cache.title(day(offset))
    }
}
extension String {
    func matchesSearch(_ query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { range(of: String($0), options: options, locale: Locale(identifier: "uk_UA")) != nil }
    }
}
