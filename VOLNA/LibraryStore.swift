import Foundation
import Combine

enum LibraryFailure: LocalizedError {
    case unavailable, oversized, invalid
    var errorDescription: String? { "Не вдалося оновити дані. Спробуйте ще раз." }
}
private final class APIRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == VolnaConfiguration.origin.host ? request : nil)
    }
}
final class APIClient: Sendable {
    private let session: URLSession
    init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 18; c.timeoutIntervalForResource = 25
        c.httpShouldSetCookies = false; c.httpCookieStorage = nil; c.urlCache = nil
        session = URLSession(configuration: c, delegate: APIRedirectGuard(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func load<T: Decodable & Sendable>(_ type: T.Type, url: URL) async throws -> (T, Data) {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.mimeType?.contains("json") == true else { throw LibraryFailure.unavailable }
        guard response.expectedContentLength <= 2_500_000 else { throw LibraryFailure.oversized }
        var data = Data(); data.reserveCapacity(64_000)
        for try await byte in bytes {
            if data.count >= 2_500_000 { throw LibraryFailure.oversized }
            if data.count % 8192 == 0 { try Task.checkCancellation() }
            data.append(byte)
        }
        return (try JSONDecoder().decode(type, from: data), data)
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var catalogue: Catalogue?
    @Published private(set) var summary: [String: GuideSummary.Entry] = [:]
    @Published private(set) var guides: [String: GuideDay] = [:]
    @Published private(set) var recordings: [String: [Recording]] = [:]
    @Published private(set) var favorites: Set<String>
    @Published private(set) var catalogueRefreshing = false
    @Published private(set) var catalogueOffline = false
    @Published private(set) var guideErrors: Set<String> = []
    @Published private(set) var archiveRecovering: Set<String> = []
    @Published private(set) var clock = Date()
    @Published var channelID: String?
    @Published var dayOffset = 0
    @Published var favoritesOnly = false
    private let api = APIClient()
    private var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    private var lastSummary = Date.distantPast
    private var summaryInFlight = false
    private var guideInFlight: Set<String> = []
    private var index = ChannelIndex(catalogue: nil)
    private var archiveChecks: [String: Date] = [:]
    private var archiveInFlight: Set<String> = []
    private let cacheRoot: URL

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "native.favorites") ?? [])
        channelID = UserDefaults.standard.string(forKey: "native.lastChannel")
        cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VOLNA-Native", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let cached = try? Data(contentsOf: cacheRoot.appendingPathComponent("catalogue.json"))
        let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        catalogue = cached.flatMap { try? JSONDecoder().decode(Catalogue.self, from: $0) }
            ?? bundled.flatMap { try? JSONDecoder().decode(Catalogue.self, from: $0) }
        index = ChannelIndex(catalogue: catalogue)
        catalogueOffline = true
        for id in ["novyi", "tet"] {
            if let data = try? Data(contentsOf: cacheRoot.appendingPathComponent("archive-\(id).json")),
               let rows = try? JSONDecoder().decode([Recording].self, from: data) {
                recordings[id] = rows.filter { $0.isPlayable(at: Date()) }; archiveRecovering.insert(id)
            }
        }
        if selectedChannel == nil { channelID = channels.first?.id }
    }
    var channels: [Channel] { index.channels }
    var selectedChannel: Channel? { channelID.flatMap { index.byID[$0] } }
    var films: [Film] { catalogue?.movies ?? [] }
    var categories: [String] { index.categories }
    var guideKey: String { (channelID ?? "") + ":" + KyivClock.key(KyivClock.day(dayOffset)) }
    var selectedGuide: GuideDay? { guides[guideKey] }

    func select(_ channel: Channel) {
        channelID = channel.id; dayOffset = 0
        UserDefaults.standard.set(channel.id, forKey: "native.lastChannel")
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites).sorted(), forKey: "native.favorites")
    }
    func now(for channel: Channel, at date: Date = Date()) -> Programme? {
        if let p = summary[channel.id]?.now, p.isCurrent(at: date) { return p }
        return guides[channel.id + ":" + KyivClock.key(date)]?.programmes.filter { $0.isCurrent(at: date) }
            .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }
    func saved(_ p: Programme, channelID: String, at date: Date = Date()) -> Recording? {
        recordings[channelID]?.filter { $0.isPlayable(at: date) && $0.overlaps(p) }.max { ($0.coveredSeconds ?? 0) < ($1.coveredSeconds ?? 0) }
    }
    func archiveForDay(channelID: String, key: String) -> [Recording] {
        (recordings[channelID] ?? []).filter {
            guard $0.isPlayable(at: Date()), let start = $0.startDate else { return false }
            return KyivClock.key(start) == key
        }.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }
    func refreshCatalogue() async {
        guard !isUITesting else { return }
        guard !catalogueRefreshing else { return }
        catalogueRefreshing = true; defer { catalogueRefreshing = false }
        do {
            let (value, data) = try await api.load(Catalogue.self, url: VolnaConfiguration.api("catalog.json"))
            guard !value.channels.isEmpty, value.channels.count <= 1000, value.movies.count <= 5000 else { throw LibraryFailure.invalid }
            index = ChannelIndex(catalogue: value)
            catalogue = value; catalogueOffline = false
            try? data.write(to: cacheRoot.appendingPathComponent("catalogue.json"), options: .atomic)
            if selectedChannel == nil { channelID = channels.first?.id }
        } catch is CancellationError { return } catch { catalogueOffline = true }
    }
    func refreshSummary(force: Bool = false) async {
        guard !isUITesting else { return }
        guard !summaryInFlight else { return }
        guard force || Date().timeIntervalSince(lastSummary) > 55 else { return }
        summaryInFlight = true; defer { summaryInFlight = false }
        do {
            let (value, _) = try await api.load(GuideSummary.self, url: VolnaConfiguration.api("api/guide"))
            guard value.status == "ok" else { return }
            if summary != value.channels { summary = value.channels }
            lastSummary = Date()
        } catch { /* Retain cached rows; now() checks their time boundaries. */ }
    }
    func refreshSelectedGuide() async {
        guard !isUITesting else { return }
        guard let id = channelID else { return }
        let day = KyivClock.key(KyivClock.day(dayOffset)), key = id + ":" + day
        guard !guideInFlight.contains(key) else { return }
        guideInFlight.insert(key); defer { guideInFlight.remove(key) }
        if guides[key] == nil, let data = try? Data(contentsOf: cacheRoot.appendingPathComponent("guide-\(id)-\(day).json")) {
            guides[key] = try? JSONDecoder().decode(GuideDay.self, from: data)
        }
        do {
            let (value, data) = try await api.load(GuideDay.self, url: VolnaConfiguration.api("api/guide", query: [.init(name: "channel", value: id), .init(name: "date", value: day)]))
            try Task.checkCancellation()
            if value.status == "ok" {
                if guides[key] != value {
                    guides[key] = value
                    try? data.write(to: cacheRoot.appendingPathComponent("guide-\(id)-\(day).json"), options: .atomic)
                }
                if guideErrors.contains(key) { guideErrors.remove(key) }
            } else { guideErrors.insert(key) }
        } catch is CancellationError { return } catch { guideErrors.insert(key) }
    }
    func refreshArchive(channelID id: String, force: Bool = false) async {
        guard !isUITesting else { return }
        guard ["novyi", "tet"].contains(id), !archiveInFlight.contains(id),
              force || Date().timeIntervalSince(archiveChecks[id] ?? .distantPast) > 55 else { return }
        archiveInFlight.insert(id); archiveChecks[id] = Date(); defer { archiveInFlight.remove(id) }
        do {
            let (value, _) = try await api.load(ArchiveCatalogue.self, url: VolnaConfiguration.api("api/archive", query: [.init(name: "channel", value: id)]))
            try Task.checkCancellation()
            if value.state?.archiveRecovering == true { archiveRecovering.insert(id) }
            else {
                let rows = value.recordings.filter { $0.channelId == id && $0.isPlayable(at: Date()) }
                if recordings[id] != rows {
                    recordings[id] = rows
                    if let data = try? JSONEncoder().encode(rows) { try? data.write(to: cacheRoot.appendingPathComponent("archive-\(id).json"), options: .atomic) }
                }
                if archiveRecovering.contains(id) { archiveRecovering.remove(id) }
            }
        } catch is CancellationError { return } catch { archiveRecovering.insert(id) }
        if let old = recordings[id] {
            let valid = old.filter { $0.isPlayable(at: Date()) }
            if old != valid { recordings[id] = valid }
        }
    }
    func refreshVisible() async {
        clock = Date()
        await refreshSummary(); await refreshSelectedGuide()
        if let id = channelID { await refreshArchive(channelID: id) }
        pruneCache()
    }
    private func pruneCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix("guide-") {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, Date().timeIntervalSince(modified) > 4 * 86400 { try? FileManager.default.removeItem(at: file) }
        }
    }
}
