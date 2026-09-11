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
let targetFps = CommandLine.arguments.count >= 4 ? Double(CommandLine.arguments[3])! : 15.0

let fileUrl = URL(fileURLWithPath: videoPath)
let asset = AVURLAsset(url: fileUrl)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let duration = CMTimeGetSeconds(asset.duration)
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

var frameIndex = 0
var currentTime: Double = 0.0
let step = 1.0 / targetFps

while currentTime <= duration {
    let time = CMTime(seconds: currentTime, preferredTimescale: 600)
    do {
        var actualTime = CMTime.zero
        let cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)
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
