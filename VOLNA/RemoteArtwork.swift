import SwiftUI
import ImageIO
import UIKit

// Image downloads and decoding stay off the main actor. Only display-sized
// thumbnails are retained, so reopening a tab does not decode full posters again.
actor ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var pending: [String: Task<UIImage?, Never>] = [:]
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 16 * 1024 * 1024, diskPath: "volna-artwork")
        session = URLSession(configuration: config)
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 64
    }
    func image(url: URL, pixels: Int) async -> UIImage? {
        guard VolnaConfiguration.mediaURL(url.absoluteString) != nil else { return nil }
        let pixels = min(1280, max(160, pixels)), key = url.absoluteString + "#\(pixels)"
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let task = pending[key] { return await task.value }
        let task = Task { await self.download(url: url, pixels: pixels) }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        if let image, let cg = image.cgImage { cache.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height) }
        return image
    }
    private func download(url: URL, pixels: Int) async -> UIImage? {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.mimeType?.hasPrefix("image/") == true,
                  response.expectedContentLength <= 6_000_000 else { return nil }
            var data = Data(); data.reserveCapacity(128_000)
            for try await byte in bytes {
                guard data.count < 6_000_000 else { return nil }
                data.append(byte)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        } catch { return nil }
    }
}

struct RemoteArtwork: View {
    let url: URL?
    var pixels = 480
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.clear }
        }.task(id: (url?.absoluteString ?? "") + "#\(pixels)") {
            image = nil
            guard let url else { return }
            let result = await ArtworkCache.shared.image(url: url, pixels: pixels)
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}
