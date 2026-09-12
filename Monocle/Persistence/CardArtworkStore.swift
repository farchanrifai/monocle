import UIKit
import ImageIO

public final class CardArtworkStore: @unchecked Sendable {
    public static let shared = CardArtworkStore()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

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
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    public func saveArtwork(_ rawData: Data, for bookID: UUID) throws -> String {
        let filename = "\(bookID.uuidString)-\(UUID().uuidString).jpg"
        guard let downsampled = downsample(imageData: rawData, maxDimension: 1200) else { throw BackupError.invalid }
        let targetURL = artworkDirectory.appendingPathComponent(filename)
        try downsampled.write(to: targetURL, options: .atomic)

        if let image = UIImage(data: downsampled) {
            cache.setObject(image, forKey: filename as NSString, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        }
        return filename
    }

    public func loadArtwork(filename: String) -> UIImage? {
        guard Self.isValidFilename(filename) else { return nil }
        if let cached = cache.object(forKey: filename as NSString) {
            return cached
        }
        let url = artworkDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: filename as NSString, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        return image
    }

    public func loadArtworkData(filename: String) -> Data? {
        guard Self.isValidFilename(filename) else { return nil }
        let url = artworkDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    public func importArtworkData(_ data: Data, filename: String) throws {
        guard Self.isValidFilename(filename) else { throw BackupError.invalid }
        guard UIImage(data: data) != nil else { throw BackupError.invalid }
        let url = artworkDirectory.appendingPathComponent(filename)
        cache.removeObject(forKey: filename as NSString)
        try data.write(to: url, options: .atomic)
        if let image = UIImage(data: data) {
            cache.setObject(image, forKey: filename as NSString, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        }
    }

    public func deleteArtwork(filename: String) {
        guard Self.isValidFilename(filename) else { return }
        cache.removeObject(forKey: filename as NSString)
        let url = artworkDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    public static func isValidFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename != "." && filename != ".." &&
        !filename.contains("/") && !filename.contains("\\") &&
        filename.rangeOfCharacter(from: .controlCharacters) == nil
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
