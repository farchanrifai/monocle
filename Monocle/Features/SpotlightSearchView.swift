import SwiftUI

enum DateFilterPreset: String, CaseIterable, Identifiable {
    case all = "All Time"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .all: return "All Time"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        }
    }
}

enum AmountFilterPreset: String, CaseIterable, Identifiable {
    case all = "Any Amount"
    case under50k = "< Rp 50k"
    case from50kTo200k = "Rp 50k - 200k"
    case over200k = "> Rp 200k"

    var id: String { rawValue }
}

struct CardSearchResults: Identifiable {
    let id: UUID
    let book: BookProfile
    let expenses: [Expense]
    let subtotal: Int64
}

struct SpotlightSearchView: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    var safeAreaTop: CGFloat = 0

    @State private var searchText = ""
    @State private var selectedDatePreset: DateFilterPreset = .all
    @State private var selectedAmountPreset: AmountFilterPreset = .all
    @State private var selectedCategoryID: UUID? = nil
    @State private var selectedCardID: UUID? = nil

    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color {
        colorScheme == .dark ? Color.white : MC.ink
    }

    private var paper: Color {
        colorScheme == .dark ? Color.black : MC.paper
    }

    private var isFilteringActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty ||
        selectedDatePreset != .all ||
        selectedAmountPreset != .all ||
        selectedCategoryID != nil ||
        selectedCardID != nil
    }

    // MARK: - Filtered Results Computation

    private var cardResults: [CardSearchResults] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let targetBooks: [BookProfile]
        if let selectedCardID {
            targetBooks = model.books.filter { $0.id == selectedCardID }
        } else {
            targetBooks = model.unhiddenBooks
        }

        var results: [CardSearchResults] = []
        let cal = Calendar.current
        let now = Date()

        for book in targetBooks {
            let allBookExpenses = model.expenses(for: book.id)
            let matching = allBookExpenses.filter { expense in
                // 1. Query matching
                if !query.isEmpty {
                    let noteMatches = expense.note.lowercased().contains(query)
                    let titleMatches = model.title(expense).lowercased().contains(query)
                    let catNameMatches = model.category(expense.categoryID)?.name.lowercased().contains(query) ?? false

                    // Amount numeric match (e.g. query "50" or "50k")
                    let cleanQuery = query.replacingOccurrences(of: "k", with: "000").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
                    let formattedAmount = Money.format(expense.amount, currency: false).lowercased()
                    let amountMatches = formattedAmount.contains(query) || (Int64(cleanQuery) != nil && (expense.amount / 100) == Int64(cleanQuery)!)

                    if !noteMatches && !titleMatches && !catNameMatches && !amountMatches {
                        return false
                    }
                }

                // 2. Date preset matching
                switch selectedDatePreset {
                case .all:
                    break
                case .today:
                    if !cal.isDateInToday(expense.date) && expense.day != Day.string(now) {
                        return false
                    }
                case .thisWeek:
                    if !cal.isDate(expense.date, equalTo: now, toGranularity: .weekOfYear) {
                        return false
                    }
                case .thisMonth:
                    if !cal.isDate(expense.date, equalTo: now, toGranularity: .month) {
                        return false
                    }
                case .lastMonth:
                    guard let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) else { return false }
                    if !cal.isDate(expense.date, equalTo: lastMonthDate, toGranularity: .month) {
                        return false
                    }
                }

                // 3. Amount preset matching (stored in minor units: 1 IDR = 100 minor units)
                switch selectedAmountPreset {
                case .all:
                    break
                case .under50k:
                    if expense.amount >= 50_000 * 100 { return false }
                case .from50kTo200k:
                    if expense.amount < 50_000 * 100 || expense.amount > 200_000 * 100 { return false }
                case .over200k:
                    if expense.amount <= 200_000 * 100 { return false }
                }

                // 4. Category matching
                if let selectedCategoryID {
                    let directMatch = expense.categoryID == selectedCategoryID
                    let splitMatch = expense.allocations.contains { $0.categoryID == selectedCategoryID }
                    if !directMatch && !splitMatch { return false }
                }

                return true
            }

            if !matching.isEmpty {
                let subtotal = matching.reduce(0) { $0 + $1.amount }
                results.append(CardSearchResults(id: book.id, book: book, expenses: matching, subtotal: subtotal))
            }
        }

        return results
    }

    private var totalCount: Int {
        cardResults.reduce(0) { $0 + $1.expenses.count }
    }

    private var totalAmount: Int64 {
        cardResults.reduce(0) { $0 + $1.subtotal }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            paper.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: safeAreaTop)

                topSearchBar
                    .padding(.top, 4)

                filterPillsBar
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if isFilteringActive {
                    filterSummaryBar
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }

                Divider()
                    .overlay(MC.line)
                    .padding(.top, 2)

                resultsScrollView
            }
        }
        .ignoresSafeArea()
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Search Bar

    private var topSearchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Search note, merchant, amount…", text: $searchText)
                    .font(.system(size: 15, weight: .regular))
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("spotlightSearchField")

                if !searchText.isEmpty {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("spotlightSearchClearButton")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .liquidGlass(cornerRadius: 14, specularIntensity: 0.28, interactive: false)

            Button("Cancel") {
                isSearchFocused = false
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                    isPresented = false
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MC.red)
            .accessibilityIdentifier("spotlightCancelButton")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Filter Pills

    private var filterPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 1. Date Pill
                Menu {
                    ForEach(DateFilterPreset.allCases) { preset in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedDatePreset = preset
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                if selectedDatePreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                        Text(selectedDatePreset == .all ? "Date" : selectedDatePreset.shortLabel)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                }
                .liquidGlassPill(isActive: selectedDatePreset != .all)
                .accessibilityIdentifier("filterDatePill")

                // 2. Amount Pill
                Menu {
                    ForEach(AmountFilterPreset.allCases) { preset in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedAmountPreset = preset
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                if selectedAmountPreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "banknote")
                            .font(.system(size: 11, weight: .semibold))
                        Text(selectedAmountPreset == .all ? "Amount" : selectedAmountPreset.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                }
                .liquidGlassPill(isActive: selectedAmountPreset != .all)
                .accessibilityIdentifier("filterAmountPill")

                // 3. Category Pill
                Menu {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedCategoryID = nil
                    } label: {
                        HStack {
                            Text("All Categories")
                            if selectedCategoryID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(model.activeCategories) { cat in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedCategoryID = cat.id
                        } label: {
                            HStack {
                                Label(cat.name, systemImage: cat.symbol)
                                if selectedCategoryID == cat.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let selectedCat = model.category(selectedCategoryID) {
                            Image(systemName: selectedCat.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(selectedCat.name)
                                .font(.system(size: 12, weight: .medium))
                        } else {
                            Image(systemName: "tag")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Category")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                }
                .liquidGlassPill(isActive: selectedCategoryID != nil)
                .accessibilityIdentifier("filterCategoryPill")

                // 4. Card Pill
                Menu {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedCardID = nil
                    } label: {
                        HStack {
                            Text("All Cards")
                            if selectedCardID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(model.unhiddenBooks) { book in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedCardID = book.id
                        } label: {
                            HStack {
                                Text(book.name)
                                if selectedCardID == book.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 11, weight: .semibold))
                        Text(selectedCardID != nil ? (model.books.first(where: { $0.id == selectedCardID })?.name ?? "Card") : "All Cards")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                }
                .liquidGlassPill(isActive: selectedCardID != nil)
                .accessibilityIdentifier("filterCardPill")
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Filter Summary Banner

    private var filterSummaryBar: some View {
        HStack {
            HStack(spacing: 4) {
                Text("\(totalCount) \(totalCount == 1 ? "RESULT" : "RESULTS")")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.secondary)

                Text("TOTAL \(Money.format(totalAmount))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ink)
            }
            .accessibilityIdentifier("spotlightResultsSummary")

            Spacer()

            Button("Reset") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy(duration: 0.18)) {
                    searchText = ""
                    selectedDatePreset = .all
                    selectedAmountPreset = .all
                    selectedCategoryID = nil
                    selectedCardID = nil
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MC.red)
            .accessibilityIdentifier("spotlightResetFiltersButton")
        }
    }

    // MARK: - Results Scroll View

    private var resultsScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if cardResults.isEmpty {
                    if isFilteringActive {
                        emptyFilterState
                    } else {
                        suggestedFiltersAndRecentActivity
                    }
                } else {
                    ForEach(cardResults) { cardResult in
                        cardGroupSection(cardResult)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
    }

    // MARK: - Card Group Section

    private func cardGroupSection(_ cardResult: CardSearchResults) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("RESULTS IN \(cardResult.book.name.uppercased())")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(Money.format(cardResult.subtotal))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 0) {
                ForEach(cardResult.expenses) { expense in
                    searchResultRow(expense, book: cardResult.book)
                }
            }
            .background(MC.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15), lineWidth: 0.5)
            )
        }
    }

    private func searchResultRow(_ expense: Expense, book: BookProfile) -> some View {
        Button {
            isSearchFocused = false
            model.edit(expense)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let cat = model.category(expense.categoryID) {
                    Image(systemName: cat.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MC.red)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.04), in: Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title(expense))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(expense.day)
                        if let cat = model.category(expense.categoryID) {
                            Text("·")
                            Text(cat.name)
                        }
                    }
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(Money.format(expense.amount))
                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityIdentifier("searchResult-\(expense.note)")
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                isSearchFocused = false
                model.edit(expense)
            }
            Button("Repeat", systemImage: "repeat") {
                model.repeatExpense(expense)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.delete(expense)
            }
        }
    }

    // MARK: - Empty & Initial States

    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 40)

            Text("No Matching Transactions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)

            Text("Try searching with different keywords or clearing active filters.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityIdentifier("spotlightEmptyState")
    }

    private var suggestedFiltersAndRecentActivity: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK FILTERS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                HStack(spacing: 8) {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedDatePreset = .thisWeek
                    } label: {
                        HStack(spacing: 4) {
                            Text("📅")
                            Text("This Week")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                    }
                    .liquidGlassPill(isActive: false)

                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedAmountPreset = .over200k
                    } label: {
                        HStack(spacing: 4) {
                            Text("💸")
                            Text("> Rp 200k")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                    }
                    .liquidGlassPill(isActive: false)

                    if let firstCat = model.activeCategories.first {
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedCategoryID = firstCat.id
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: firstCat.symbol)
                                    .font(.system(size: 11))
                                Text(firstCat.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                        }
                        .liquidGlassPill(isActive: false)
                    }
                }
            }

            // Recent activity preview
            let recentActivities = model.activities(selectedBookID: nil, allBooks: true).prefix(8)
            if !recentActivities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT TRANSACTIONS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(recentActivities)) { expense in
                            if let book = model.books.first(where: { $0.id == expense.bookID }) {
                                searchResultRow(expense, book: book)
                            }
                        }
                    }
                    .background(MC.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }
}
