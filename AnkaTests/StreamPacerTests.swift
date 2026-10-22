import SwiftUI
import XCTest
@testable import Anka

@MainActor
final class StreamPacerTests: XCTestCase {
    func testRevealsAtASteadyRateAndCatchesUpWhenBackedUp() {
        let pacer = StreamPacer()
        pacer.set(String(repeating: "a", count: 90))
        let start = Date()
        _ = pacer.advance(to: start)
        // 60fps for one second: the base rate is 45 chars/s, a big backlog speeds that up but never past the text.
        var shown = 0.0
        for frame in 1...60 { shown = pacer.advance(to: start.addingTimeInterval(Double(frame) / 60)) }
        XCTAssertGreaterThan(shown, 40)
        XCTAssertLessThanOrEqual(shown, 90)
        XCTAssertEqual(pacer.visible.count, Int(shown.rounded(.up)))
        for frame in 61...400 { shown = pacer.advance(to: start.addingTimeInterval(Double(frame) / 60)) }
        XCTAssertEqual(shown, 90, "catches up fully")
        XCTAssertTrue(pacer.caughtUp)
        pacer.reset()
        XCTAssertEqual(pacer.visible, "")
    }

    func testFadeRendererMakesTheNewestGlyphsFainter() throws {
        func alphaProfile(shown: Double?) throws -> (first: Double, last: Double) {
            let view = Text("Hello streaming world").font(.system(size: 20, weight: .bold)).foregroundStyle(.black)
                .textRenderer(StreamFadeRenderer(shown: shown))
                .padding(4).background(.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let data = try XCTUnwrap(image.dataProvider?.data as Data?)
            // Darkest pixel in the left third vs the right third of the text row.
            func darkest(_ range: Range<Int>) -> Double {
                var best = 255
                for y in 0..<image.height { for x in range {
                    let offset = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
                    best = min(best, Int(data[offset]))
                } }
                return Double(best)
            }
            let w = image.width
            return (darkest(4..<(w / 3)), darkest((2 * w / 3)..<(w - 4)))
        }
        let plain = try alphaProfile(shown: nil)
        XCTAssertLessThan(plain.last, 60, "unfaded text is dark everywhere")
        // 21 characters shown, the newest just arrived: the first glyphs are fully dark, the last ones barely visible.
        let fading = try alphaProfile(shown: 20.1)
        XCTAssertLessThan(fading.first, 60)
        XCTAssertGreaterThan(fading.last, plain.last + 40, "the newest glyphs are lighter while they fade in")
    }
}
