import UIKit
import ImageIO

public final class CardArtworkStore: @unchecked Sendable {
    public static let shared = CardArtworkStore()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let customDirectory: URL?
    var writeFault: ((String) throws -> Void)? // deterministic write failures for recovery tests
    static let maximumDimension = 1_200
    static let maximumAssetBytes = 8 * 1024 * 1024

    public var artworkDirectory: URL {
        if let customDirectory { return customDirectory }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("CardArtwork", isDirectory: true)
    }

    public init(directory: URL? = nil) {
        customDirectory = directory
        cache.countLimit = 50
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// Inspect dimensions before decoding, so a small compressed input cannot
    /// allocate an unbounded image during preview or ordinary card rendering.
    static func validateArtworkData(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumAssetBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (1...maximumDimension).contains(width), (1...maximumDimension).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width == width, image.height == height else { throw BackupError.invalid }
    }

    /// Stage validated bytes in the operation's private directory before SQLite
    /// activation. No active artwork or cache changes occur while previewing.
    func stageArtworks(_ artworks: [String: Data], in directory: URL) throws -> URL {
        let staging = directory.appendingPathComponent("restore-artworks-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for (filename, data) in artworks {
                guard Self.isValidFilename(filename) else { throw BackupError.invalid }
                try Self.validateArtworkData(data)
                try data.write(to: staging.appendingPathComponent(filename), options: .atomic)
            }
            return staging
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func installStagedArtworks(_ directory: URL) throws {
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try importArtworkData(Data(contentsOf: url), filename: url.lastPathComponent)
        }
    }

    public func saveArtwork(_ rawData: Data, for bookID: UUID) throws -> String {
        let filename = "\(bookID.uuidString)-\(UUID().uuidString).jpg"
        guard let downsampled = downsample(imageData: rawData, maxDimension: 1200) else { throw BackupError.invalid }
        try importArtworkData(downsampled, filename: filename)

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
              (try? Self.validateArtworkData(data)) != nil,
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
        try Self.validateArtworkData(data)
        try writeFault?(filename)
        try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
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

    public func deleteAllArtworks() {
        cache.removeAllObjects()
        if let files = try? fileManager.contentsOfDirectory(atPath: artworkDirectory.path) {
            for file in files {
                let url = artworkDirectory.appendingPathComponent(file)
                try? fileManager.removeItem(at: url)
            }
        }
    }

    public static func isValidFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename.utf8.count <= 255 && filename != "." && filename != ".." &&
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
