import AVKit
import Combine
import SwiftUI
import MediaPlayer

enum PlaybackQuality: String, CaseIterable, Identifiable {
    case automatic, economical
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: return "Автоматично · без обмеження"; case .economical: return "Економія трафіку" }
    }
    var maximumBitrate: Double {
        switch self { case .automatic: return 0; case .economical: return 1_500_000 }
    }
}

@MainActor
final class PlaybackStore: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var title = ""
    @Published private(set) var subtitle = ""
    @Published private(set) var channelID: String?
    @Published private(set) var recordingID: String?
    @Published private(set) var filmID: String?
    @Published private(set) var loading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?
    @Published private(set) var active = false
    @Published private(set) var resolution: String?
    @Published private(set) var slowConnection = false
    @Published private(set) var audioOptions: [AVMediaSelectionOption] = []
    @Published private(set) var subtitleOptions: [AVMediaSelectionOption] = []
    @Published var quality: PlaybackQuality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "native.quality"); applyQuality() }
    }
    @Published var settingsPresented = false
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var cancellables: Set<AnyCancellable> = []
    private var itemCancellables: Set<AnyCancellable> = []
    private var currentURL: URL?
    private var initialOffset: Double = 0
    private var playbackLimit: Double?
    private var generation = UUID()
    private var trackTask: Task<Void, Never>?
    private var waitingTask: Task<Void, Never>?
    private var notificationTokens: [NSObjectProtocol] = []

    init() {
        quality = PlaybackQuality(rawValue: UserDefaults.standard.string(forKey: "native.quality") ?? "") ?? .automatic
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        player.publisher(for: \.timeControlStatus).receive(on: DispatchQueue.main).sink { [weak self] status in
            guard let self else { return }
            self.isPlaying = status == .playing
            if self.player.currentItem?.status == .readyToPlay { self.loading = status == .waitingToPlayAtSpecifiedRate }
            self.waitingTask?.cancel(); self.slowConnection = false
            if status == .waitingToPlayAtSpecifiedRate {
                let request = self.generation
                self.waitingTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                    guard let self, self.generation == request, self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
                    self.slowConnection = true
                }
            }
        }.store(in: &cancellables)
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let number = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: number) == .began else { return }
            Task { @MainActor in self?.player.pause() }
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let number = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: number) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.player.pause() }
        })
    }

    deinit { trackTask?.cancel(); waitingTask?.cancel(); notificationTokens.forEach { NotificationCenter.default.removeObserver($0) } }
    var isLive: Bool { channelID != nil && recordingID == nil }
    var hasVideo: Bool { active && player.currentItem != nil }

    func play(channel: Channel, programme: Programme?) {
        guard let url = channel.nativeSource?.nativeURL else { error = "У цього каналу поки немає сумісного відеоджерела."; return }
        channelID = channel.id; recordingID = nil; filmID = nil
        title = channel.title; subtitle = programme?.title ?? "Прямий ефір"
        start(url: url, offset: 0, limit: nil)
    }
    func play(recording: Recording, channel: Channel) {
        guard recording.isPlayable(at: Date()), let url = recording.nativeURL else { error = "Цей запис уже недоступний."; return }
        channelID = channel.id; recordingID = recording.id; filmID = nil
        title = recording.title; subtitle = channel.title + " · " + recording.label
        start(url: url, offset: recording.offset, limit: recording.status == "recording" ? nil : recording.playbackLimit)
    }
    func play(film: Film) {
        guard let url = film.nativeSource?.nativeURL else { return }
        channelID = nil; recordingID = nil; filmID = film.id
        title = film.title; subtitle = [film.year.map(String.init), film.genre].compactMap { $0 }.joined(separator: " · ")
        start(url: url, offset: 0, limit: nil)
    }
    func retry() {
        guard let currentURL else { return }
        let position = player.currentTime().seconds
        start(url: currentURL, offset: isLive ? 0 : max(initialOffset, position.isFinite ? position : 0), limit: playbackLimit)
    }
    func stop() {
        generation = UUID(); trackTask?.cancel(); waitingTask?.cancel(); itemCancellables.removeAll()
        player.pause(); player.replaceCurrentItem(with: nil)
        active = false; loading = false; slowConnection = false; error = nil; currentURL = nil
        channelID = nil; recordingID = nil; filmID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func toggle() { if player.timeControlStatus == .playing { player.pause() } else { player.play() } }
    func audio(_ option: AVMediaSelectionOption) { if let audioGroup { player.currentItem?.select(option, in: audioGroup) } }
    func subtitles(_ option: AVMediaSelectionOption?) { if let subtitleGroup { player.currentItem?.select(option, in: subtitleGroup) } }

    private func start(url: URL, offset: Double, limit: Double?) {
        generation = UUID(); let request = generation
        trackTask?.cancel(); waitingTask?.cancel(); itemCancellables.removeAll()
        player.pause(); currentURL = url; initialOffset = offset; playbackLimit = limit
        audioOptions = []; subtitleOptions = []; audioGroup = nil; subtitleGroup = nil
        loading = true; error = nil; active = true; resolution = nil; slowConnection = false
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { self.error = "Не вдалося увімкнути звук. Спробуйте ще раз."; loading = false; return }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = isLive ? 12 : 30
        item.preferredPeakBitRate = quality.maximumBitrate
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        if let limit { item.forwardPlaybackEndTime = CMTime(seconds: limit, preferredTimescale: 600) }
        player.replaceCurrentItem(with: item)
        item.publisher(for: \.presentationSize).receive(on: DispatchQueue.main).sink { [weak self] size in
            guard let self, self.generation == request, size.width > 0, size.height > 0 else { return }
            self.resolution = "\(Int(size.width)) × \(Int(size.height))"
        }.store(in: &itemCancellables)
        item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self, weak item] status in
            guard let self, let item, self.generation == request else { return }
            switch status {
            case .readyToPlay:
                self.loading = false
                if offset > 0 {
                    self.player.seek(to: CMTime(seconds: offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] done in
                        Task { @MainActor in
                            guard let self, self.generation == request else { return }
                            if done { self.player.play() }
                        }
                    }
                } else { self.player.play() }
                self.loadTracks(asset: item.asset, generation: request)
            case .failed:
                self.loading = false
                self.error = "Джерело тимчасово не відповідає. Натисніть «Повторити» або оберіть інший канал."
            default: break
            }
        }.store(in: &itemCancellables)
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.generation == request else { return }
                self.loading = false; self.error = "Відтворення перервалося. Можна повторити з поточної позиції."
            }.store(in: &itemCancellables)
        waitingTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.generation == request, self.loading, !self.isPlaying else { return }
            self.slowConnection = true
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: subtitle, MPNowPlayingInfoPropertyIsLiveStream: isLive]
    }
    private func loadTracks(asset: AVAsset, generation request: UUID) {
        trackTask = Task { [weak self] in
            do {
                let audio = try await asset.loadMediaSelectionGroup(for: .audible)
                let subtitles = try await asset.loadMediaSelectionGroup(for: .legible)
                try Task.checkCancellation()
                guard let self, self.generation == request else { return }
                self.audioGroup = audio; self.subtitleGroup = subtitles
                self.audioOptions = audio?.options ?? []; self.subtitleOptions = subtitles?.options ?? []
                if let audio, let preferred = audio.options.first(where: { ["uk", "ukr", "ru", "rus"].contains($0.extendedLanguageTag?.lowercased() ?? $0.locale?.languageCode ?? "") }) {
                    self.player.currentItem?.select(preferred, in: audio)
                }
            } catch { /* A stream may expose no alternate tracks. */ }
        }
    }
    private func applyQuality() {
        player.currentItem?.preferredPeakBitRate = quality.maximumBitrate
        // Zero means no artificial resolution cap; AVFoundation adapts to the source/network.
        player.currentItem?.preferredMaximumResolution = .zero
    }
}

struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}

struct PlaybackSettings: View {
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Якість") {
                    if let resolution = playback.resolution { LabeledContent("Поточне відео", value: resolution) }
                    Picker("Режим", selection: $playback.quality) {
                        ForEach(PlaybackQuality.allCases) { quality in Text(quality.title).tag(quality) }
                    }.pickerStyle(.inline)
                    Text("Якість залежить від джерела. Режим економії обмежує бітрейт; він не додає відсутні HD-версії.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Озвучення") {
                    if playback.audioOptions.isEmpty { Text("Джерело не надало окремих аудіодоріжок").foregroundStyle(.secondary) }
                    ForEach(Array(playback.audioOptions.enumerated()), id: \.offset) { _, option in
                        Button(option.displayName) { playback.audio(option); dismiss() }
                    }
                }
                if !playback.subtitleOptions.isEmpty {
                    Section("Субтитри") {
                        Button("Вимкнути") { playback.subtitles(nil); dismiss() }
                        ForEach(Array(playback.subtitleOptions.enumerated()), id: \.offset) { _, option in
                            Button(option.displayName) { playback.subtitles(option); dismiss() }
                        }
                    }
                }
            }.navigationTitle("Налаштування відео")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
