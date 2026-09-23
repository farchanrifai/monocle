import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

public final class CardArtworkStore: @unchecked Sendable {
    public static let shared = CardArtworkStore()

    private let cache = NSCache<NSString, PlatformImage>()
    private let fileManager = FileManager.default

    public var artworkDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        #if os(macOS)
        let dir = appSupport.appendingPathComponent("monocle-mac/CardArtwork", isDirectory: true)
        #else
        let dir = appSupport.appendingPathComponent("CardArtwork", isDirectory: true)
        #endif
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

        if let image = Self.decodeImage(downsampled) {
            cache.setObject(image, forKey: filename as NSString, cost: downsampled.count)
        }
        return filename
    }

    public func loadArtwork(filename: String) -> PlatformImage? {
        guard Self.isValidFilename(filename) else { return nil }
        if let cached = cache.object(forKey: filename as NSString) {
            return cached
        }
        let url = artworkDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let image = Self.decodeImage(data) else {
            return nil
        }
        cache.setObject(image, forKey: filename as NSString, cost: data.count)
        return image
    }

    public func loadArtworkData(filename: String) -> Data? {
        guard Self.isValidFilename(filename) else { return nil }
        let url = artworkDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    public func importArtworkData(_ data: Data, filename: String) throws {
        guard Self.isValidFilename(filename) else { throw BackupError.invalid }
        guard CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw BackupError.invalid }
        let url = artworkDirectory.appendingPathComponent(filename)
        cache.removeObject(forKey: filename as NSString)
        try data.write(to: url, options: .atomic)
        if let image = Self.decodeImage(data) {
            cache.setObject(image, forKey: filename as NSString, cost: data.count)
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
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, downsampledImage, [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func decodeImage(_ data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }
}
