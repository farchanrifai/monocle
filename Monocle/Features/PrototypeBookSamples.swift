import Foundation

struct PrototypeBook: Identifiable {
    let id: Int
    var name: String
}

struct PrototypeActivity: Identifiable {
    let id: UUID
    let bookID: Int
    var title: String
    var amount: Int64
    var day: String
}

enum PrototypeBookSamples {
    static let books: [PrototypeBook] = [
        PrototypeBook(id: 1, name: "Everyday"),
        PrototypeBook(id: 2, name: "Tokyo / September"),
        PrototypeBook(id: 3, name: "A fresh start"),
        PrototypeBook(id: 4, name: "Studio project"),
        PrototypeBook(id: 5, name: "The very long name of our next family adventure"),
        PrototypeBook(id: 6, name: "Home essentials")
    ]

    static let activities: [PrototypeActivity] = {
        let bookIDs = [1, 2, 4, 5, 6]
        let titles = [
            ["Morning coffee", "Groceries", "Lunch", "Train ride"],
            ["Airport train", "Ramen", "Museum tickets", "Hotel"],
            ["Sketchbook", "Print samples", "Materials", "Studio supplies"],
            ["Trip deposit", "Guidebook", "Travel adapters", "Day tickets"],
            ["Internet", "Cleaning supplies", "Laundry", "Light bulbs"]
        ]
        let amounts: [Int64] = [32_000, 185_000, 58_000, 24_000]
        return (0..<120).map { index in
            let bookIndex = index % bookIDs.count
            let itemIndex = (index / bookIDs.count) % 4
            // ISO dates keep the fixture portable and sort without locale parsing.
            let day = String(format: "2026-%02d-%02d", 9 - index / 28, 28 - index % 28)
            return PrototypeActivity(
                id: UUID(), bookID: bookIDs[bookIndex],
                title: titles[bookIndex][itemIndex],
                amount: amounts[itemIndex] * 100 * Int64(bookIndex + 1), day: day
            )
        }
    }()

    static func activities(
        _ values: [PrototypeActivity], selectedBookID: Int?,
        visibleBookIDs: Set<Int>, allBooks: Bool
    ) -> [PrototypeActivity] {
        values.filter { activity in
            if let selectedBookID { return activity.bookID == selectedBookID }
            return allBooks || visibleBookIDs.contains(activity.bookID)
        }.sorted { $0.day > $1.day }
    }
}
