import UIKit
import ImageIO

public final class CardArtworkStore: @unchecked Sendable {
    public static let shared = CardArtworkStore()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.farchan.monocle.cardartwork", qos: .userInitiated)

    public var artworkDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = appSupport.appendingPathComponent("CardArtwork", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public init() {
        cache.countLimit = 50
    }

    public func saveArtwork(_ rawData: Data, for bookID: UUID) throws -> String {
        let filename = "\(bookID.uuidString).jpg"
        let downsampled = downsample(imageData: rawData, maxDimension: 1200) ?? rawData
        let targetURL = artworkDirectory.appendingPathComponent(filename)
        try downsampled.write(to: targetURL, options: .atomic)

        if let image = UIImage(data: downsampled) {
            cache.setObject(image, forKey: filename as NSString)
        }
        return filename
    }

    public func loadArtwork(filename: String) -> UIImage? {
        if let cached = cache.object(forKey: filename as NSString) {
            return cached
        }
        let url = artworkDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }

    public func loadArtworkData(filename: String) -> Data? {
        let url = artworkDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    public func importArtworkData(_ data: Data, filename: String) throws {
        let url = artworkDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        if let image = UIImage(data: data) {
            cache.setObject(image, forKey: filename as NSString)
        }
    }

    public func deleteArtwork(filename: String) {
        cache.removeObject(forKey: filename as NSString)
        let url = artworkDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    private func downsample(imageData: Data, maxDimension: CGFloat) -> Data? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, options) else {
            return nil
        }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        let uiImage = UIImage(cgImage: downsampledImage)
        return uiImage.jpegData(compressionQuality: 0.85)
    }
}
