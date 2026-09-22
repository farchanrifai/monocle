import ActivityKit
import Foundation

public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var updatedAt: Date
    public var activeBook: WidgetBookSummary
    public var activeStack: WidgetStackSummary?
    public var cycleBudget: WidgetBudgetSummary?
    public var todaySpending: WidgetTodaySummary
    public var quickCategories: [WidgetCategoryItem]

    public init(
        updatedAt: Date = .now,
        activeBook: WidgetBookSummary,
        activeStack: WidgetStackSummary? = nil,
        cycleBudget: WidgetBudgetSummary?,
        todaySpending: WidgetTodaySummary,
        quickCategories: [WidgetCategoryItem]
    ) {
        self.updatedAt = updatedAt
        self.activeBook = activeBook
        self.activeStack = activeStack
        self.cycleBudget = cycleBudget
        self.todaySpending = todaySpending
        self.quickCategories = quickCategories
    }

    public static let sample = WidgetSnapshot(
        updatedAt: .now,
        activeBook: WidgetBookSummary(id: UUID(), name: "Daily", tintColorHex: "E63946"),
        activeStack: WidgetStackSummary(
            id: UUID(),
            name: "Personal",
            icon: "rectangle.stack",
            cardCount: 3,
            totalSpent: 1_250_000_00,
            cardNames: ["Daily", "Groceries", "Coffee"]
        ),
        cycleBudget: WidgetBudgetSummary(
            limit: 5_000_000_00,
            spent: 2_150_000_00,
            remaining: 2_850_000_00,
            percentage: 0.43,
            daysRemaining: 18,
            dailyPaceRemaining: 158_333_00,
            cycleStartDate: Calendar.current.date(byAdding: .day, value: -12, to: .now) ?? .now,
            cycleEndDate: Calendar.current.date(byAdding: .day, value: 18, to: .now) ?? .now,
            cycleLabel: "Sep 1 – Sep 30"
        ),
        todaySpending: WidgetTodaySummary(
            totalSpent: 85_000_00,
            transactionCount: 2,
            recentTransactions: [
                WidgetTransactionItem(
                    id: UUID(),
                    title: "Kopi Kenangan",
                    amount: 35_000_00,
                    categoryName: "Coffee",
                    categorySymbol: "cup.and.saucer.fill",
                    day: "Today",
                    timeFormatted: "09:41"
                ),
                WidgetTransactionItem(
                    id: UUID(),
                    title: "Lunch Express",
                    amount: 50_000_00,
                    categoryName: "Food",
                    categorySymbol: "fork.knife",
                    day: "Today",
                    timeFormatted: "12:15"
                )
            ]
        ),
        quickCategories: [
            WidgetCategoryItem(id: UUID(), name: "Coffee", symbol: "cup.and.saucer.fill"),
            WidgetCategoryItem(id: UUID(), name: "Food", symbol: "fork.knife"),
            WidgetCategoryItem(id: UUID(), name: "Commute", symbol: "car.fill")
        ]
    )
}

public struct WidgetBookSummary: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var tintColorHex: String?

    public init(id: UUID, name: String, tintColorHex: String? = nil) {
        self.id = id
        self.name = name
        self.tintColorHex = tintColorHex
    }
}

public struct WidgetStackSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var cardCount: Int
    public var totalSpent: Int64
    public var cardNames: [String]

    public init(
        id: UUID,
        name: String,
        icon: String = "rectangle.stack",
        cardCount: Int = 0,
        totalSpent: Int64 = 0,
        cardNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.cardCount = cardCount
        self.totalSpent = totalSpent
        self.cardNames = cardNames
    }
}

public struct WidgetBudgetSummary: Codable, Sendable, Equatable {
    public var limit: Int64
    public var spent: Int64
    public var remaining: Int64
    public var percentage: Double
    public var daysRemaining: Int
    public var dailyPaceRemaining: Int64
    public var cycleStartDate: Date
    public var cycleEndDate: Date
    public var cycleLabel: String

    public init(
        limit: Int64,
        spent: Int64,
        remaining: Int64,
        percentage: Double,
        daysRemaining: Int,
        dailyPaceRemaining: Int64,
        cycleStartDate: Date,
        cycleEndDate: Date,
        cycleLabel: String
    ) {
        self.limit = limit
        self.spent = spent
        self.remaining = remaining
        self.percentage = percentage
        self.daysRemaining = daysRemaining
        self.dailyPaceRemaining = dailyPaceRemaining
        self.cycleStartDate = cycleStartDate
        self.cycleEndDate = cycleEndDate
        self.cycleLabel = cycleLabel
    }
}

public struct WidgetTransactionItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var bookID: UUID?
    public var title: String
    public var amount: Int64
    public var categoryName: String
    public var categorySymbol: String
    public var day: String
    public var timeFormatted: String

    public init(
        id: UUID,
        bookID: UUID? = nil,
        title: String,
        amount: Int64,
        categoryName: String,
        categorySymbol: String,
        day: String,
        timeFormatted: String
    ) {
        self.id = id
        self.bookID = bookID
        self.title = title
        self.amount = amount
        self.categoryName = categoryName
        self.categorySymbol = categorySymbol
        self.day = day
        self.timeFormatted = timeFormatted
    }
}

public struct WidgetTodaySummary: Codable, Sendable, Equatable {
    public var totalSpent: Int64
    public var transactionCount: Int
    public var recentTransactions: [WidgetTransactionItem]

    public init(
        totalSpent: Int64,
        transactionCount: Int,
        recentTransactions: [WidgetTransactionItem]
    ) {
        self.totalSpent = totalSpent
        self.transactionCount = transactionCount
        self.recentTransactions = recentTransactions
    }
}

public struct WidgetCategoryItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String

    public init(id: UUID, name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

// MARK: - Live Activity Attributes

public struct SpendingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var currentSpent: Int64
        public var itemCount: Int
        public var latestItemNote: String?
        public var latestItemCategorySymbol: String?
        public var sessionBudgetLimit: Int64?
        public var isPaused: Bool

        public init(
            currentSpent: Int64,
            itemCount: Int,
            latestItemNote: String? = nil,
            latestItemCategorySymbol: String? = nil,
            sessionBudgetLimit: Int64? = nil,
            isPaused: Bool = false
        ) {
            self.currentSpent = currentSpent
            self.itemCount = itemCount
            self.latestItemNote = latestItemNote
            self.latestItemCategorySymbol = latestItemCategorySymbol
            self.sessionBudgetLimit = sessionBudgetLimit
            self.isPaused = isPaused
        }
    }

    public var sessionName: String
    public var bookName: String
    public var startTime: Date
    public var bookID: UUID?

    public init(sessionName: String, bookName: String, startTime: Date = .now, bookID: UUID? = nil) {
        self.sessionName = sessionName
        self.bookName = bookName
        self.startTime = startTime
        self.bookID = bookID
    }
}
