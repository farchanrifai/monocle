import AVFoundation
import CoreGraphics
import ImageIO
import Foundation

guard CommandLine.arguments.count >= 3 else {
    print("Usage: swift extract_frames.swift <videoPath> <outputDir> [fps]")
    exit(1)
}

let videoPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]
guard let targetFps = CommandLine.arguments.count >= 4 ? Double(CommandLine.arguments[3]) : 15.0,
      targetFps.isFinite, targetFps > 0, targetFps <= 120 else {
    print("FPS must be a finite number between 0 and 120.")
    exit(1)
}

let fileUrl = URL(fileURLWithPath: videoPath)
guard FileManager.default.fileExists(atPath: fileUrl.path) else {
    print("Input video does not exist: \(videoPath)")
    exit(1)
}
let asset = AVURLAsset(url: fileUrl)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

guard let assetDuration = try? await asset.load(.duration) else {
    print("Cannot read the video duration.")
    exit(1)
}
let duration = CMTimeGetSeconds(assetDuration)
guard duration.isFinite, duration > 0 else { exit(1) }
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

var frameIndex = 0
var currentTime: Double = 0.0
let step = 1.0 / targetFps

while currentTime < duration {
    let time = CMTime(seconds: currentTime, preferredTimescale: 600)
    do {
        let (cgImage, _) = try await generator.image(at: time)
        let frameFile = URL(fileURLWithPath: outputDir).appendingPathComponent(String(format: "frame_%04d.jpg", frameIndex))
        if let destination = CGImageDestinationCreateWithURL(frameFile as CFURL, "public.jpeg" as CFString, 1, nil) {
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
        frameIndex += 1
    } catch {
        // end or skip
    }
    currentTime += step
}
print("Extracted \(frameIndex) frames to \(outputDir)")
