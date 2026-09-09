import Foundation

// Run: swiftc -module-cache-path /tmp/monocle-prototype-module-cache Monocle/Features/PrototypeBookSamples.swift scripts/check-book-prototype.swift -o /tmp/check-book-prototype && /tmp/check-book-prototype
@main
struct CheckBookPrototype {
    static func main() {
        let samples = PrototypeBookSamples.activities
        let visible = PrototypeBookSamples.activities(samples, selectedBookID: nil, visibleBookIDs: [1, 2], allBooks: false)
        assert(visible.count == 48)
        assert(visible.allSatisfy { [1, 2].contains($0.bookID) })
        let all = PrototypeBookSamples.activities(samples, selectedBookID: nil, visibleBookIDs: [], allBooks: true)
        assert(all.count == 120)
        assert(zip(all, all.dropFirst()).allSatisfy { $0.day >= $1.day })
        let selected = PrototypeBookSamples.activities(samples, selectedBookID: 4, visibleBookIDs: [1], allBooks: true)
        assert(selected.count == 24 && selected.allSatisfy { $0.bookID == 4 })
        assert(PrototypeBookSamples.activities(samples, selectedBookID: 3, visibleBookIDs: [3], allBooks: true).isEmpty)
        assert(PrototypeBookSamples.activities(samples, selectedBookID: nil, visibleBookIDs: [], allBooks: false).isEmpty)
        print("Book prototype checks passed")
    }
}
