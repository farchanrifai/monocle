import Foundation
import FoundationModels

/// Apple Intelligence (on-device Foundation Models) behind the same tools as ChatAgent, so both can be
/// compared on the same prompts. FoundationModels runs the tool loop itself; the tools reuse ChatAgent's
/// JSON schemas and ToolExecutor, so amounts and proposal cards come from the same app code.
@MainActor
final class AppleChatAgent: ChatBackend {
    private let model: AppModel
    private var session: LanguageModelSession?
    /// The target card's categories baked into the session's proposal tools as an enum.
    private var sessionCategories: [String] = []
    private var notes: [String] = []
    /// The period of the last answer, repeated in app_context so a follow-up that names none keeps it.
    private var lastPeriod: String?
    /// The current turn's executor and the cards its tool calls produced.
    private var executor: ToolExecutor?
    private var outputs: [ChatAgent.Output] = []
    /// Every tool call and result this agent made, for tuning the on-device model (AppleChatTests prints it).
    private(set) var toolLog: [String] = []

    init(model: AppModel) { self.model = model }

    /// Why the on-device model can't run here, or nil when it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to use on-device chat."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading. Try again later."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    func note(_ text: String) { notes.append(text) }

    // ponytail: on-device history lives only in the session; a relaunch or backend switch starts fresh.
    func reset() { session = nil; notes = []; lastPeriod = nil }

    func send(_ text: String, scope: AnalyticsFilterScope, now: Date) async -> [ChatAgent.Output] {
        if let reason = Self.unavailableReason { return [.error(reason)] }
        let executor = ToolExecutor(model: model, scope: scope, now: now)
        self.executor = executor
        let prompt = ([ChatAgent.context(executor, now: now, listCategories: false, lastPeriod: lastPeriod)] + notes.map { "App note: \($0)" } + [text]).joined(separator: "\n\n")
        var notice: [ChatAgent.Output] = []
        let categories = ((try? executor.targetCard()).flatMap { try? model.activeCategories(in: $0.id) } ?? []).map(\.name)
        // ponytail: tools are fixed per session, so a different card's categories start a fresh one (history lost).
        if categories != sessionCategories { session = nil; sessionCategories = categories }
        // The context window is small (~4k tokens): if a long conversation fails, retry once in a fresh session.
        for attempt in 0..<2 {
            outputs = []
            let fresh = session == nil
            let session = self.session ?? makeSession()
            self.session = session
            do {
                // Greedy: tool choice and arguments stay the same for the same prompt, which makes tuning comparable.
                let reply = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy)).content
                notes = []
                return notice + outputs + (reply.isEmpty || Self.claimsDone(reply, beside: outputs) ? [] : [.text(reply)])
            } catch {
                self.session = nil
                if fresh || attempt == 1 {
                    return notice + outputs.filter { if case .text = $0 { false } else { true } } + [.error(error.localizedDescription)]
                }
                notice = [.notice("Started a fresh conversation to keep chat fast.")]
            }
        }
        return notice
    }

    private func makeSession() -> LanguageModelSession {
        let run: @Sendable (String, String) async -> String = { [weak self] name, input in
            await self?.runTool(name, input) ?? #"{"error": "Chat was closed."}"#
        }
        let tools: [any Tool] = ChatAgent.tools.compactMap { json in
            guard let name = json["name"] as? String, let schema = json["input_schema"] as? [String: Any],
                  let parameters = try? GenerationSchema(root: Self.schema(schema, name: name, categories: sessionCategories), dependencies: []) else { return nil }
            return ExecutorTool(name: name, description: json["description"] as? String ?? "", parameters: parameters, run: run)
        }
        return LanguageModelSession(tools: tools, instructions: ChatAgent.systemPrompt + "\n" + Self.extraInstructions)
    }

    /// The small model asks permission instead of calling tools, misreads rb/jt and echoes app_context; these lines push back.
    static let extraInstructions = """
    A new purchase ("bensin 100rb kemarin") is always propose_expense with its day set, even if a similar expense exists.
    One amount followed by a colon and parts ("pasar 50rb: 30rb makan 20rb belanja") is ONE purchase: call propose_expense once with amount 50rb, note Pasar and split [Food & Drink 30rb, Shopping 20rb]. Never propose the parts separately.
    Call the tool right away: the app shows its result as a card the user confirms. Never ask "shall I add it?" and never say added, saved, updated or deleted. If no category fits clearly, pick the closest one.
    Write every amount exactly as the user wrote it (28rb, 100k, 1,5jt); the app converts it.
    note is a short name of what was bought, from the user's words, e.g. Kopi, Bensin, Lunch.
    "kemarin" is the day before Today in app_context. "tanggal 5" means day 5 of the month.
    "tiap bulan", "per bulan", "monthly" and subscriptions use propose_bill.
    Only when the user says "ganti", "ubah", "hapus", "change" or "delete": call query_expenses with period last_90_days and text set to the item word, then call propose_edit or propose_delete with the id it returns. Ask only when two or more expenses match.
    For comparisons, repeat the summary field from compare_periods.
    For "breakdown", "what categories" or "where does my money go", call get_summary with group_by category and name the top two or three categories with their amounts and share.
    For "how am I doing" or "overview", call get_insights with kind overview. "On track", "on pace" or "will I go over": kind pace. "Compared to last month so far": kind month_over_month. "Budget history" or "past cycles": kind budget_history. "Biggest", "largest" or "most expensive": kind top_expenses.
    "By payment method", "cash vs card" or "paid with": get_summary with group_by paid_with. "Which day of the week": group_by weekday. Repeat the summary field when a result has one.
    If a period has no spending, say so in a few words, then call get_summary for last_month and describe that instead.
    A follow-up ("how about last month?", "what categories?", "and transport?") keeps the period and scope of the previous question.
    Omit scope and card unless the user names one.
    Never repeat <app_context>. Never show ids.
    """

    /// The small model ignores "never say saved" and writes "has been updated" next to a card the user hasn't
    /// confirmed yet. The card says what will happen, so that sentence is dropped rather than shown wrong.
    static func claimsDone(_ reply: String, beside outputs: [ChatAgent.Output]) -> Bool {
        let hasCard = outputs.contains { switch $0 { case .proposal, .change, .bill: true; default: false } }
        // ponytail: word list, not a classifier; extend it when a new phrasing slips through.
        let done = #"\b(added|saved|updated|changed|deleted|removed|recorded|logged|created|ditambahkan|disimpan|diubah|diperbarui|dihapus|dicatat|dibuat)\b"#
        return hasCard && reply.range(of: done, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func runTool(_ name: String, _ input: String) -> String {
        guard let executor else { return #"{"error": "No active turn."}"# }
        // Amounts arrive as the user wrote them ("100rb", "4.50"); app code turns them into numbers for ToolExecutor.
        // ponytail: parsed in the target card's currency even when the call names another card.
        let code = (try? executor.targetCard()).map { executor.model.currency(ofCard: $0.id) } ?? Money.reportingCurrency
        var json = (try? JSONSerialization.jsonObject(with: Data(input.utf8))).map { Self.clean($0, code: code) } as? [String: Any]
        // The model echoes the current card as scope/card; the default means the same and avoids a stack/card name clash.
        if (json?["scope"] as? String).map(Self.folded) == Self.folded(executor.scope.title) { json?["scope"] = nil }
        if let card = json?["card"] as? String, (try? executor.targetCard()).map({ Self.folded($0.name) }) == Self.folded(card) { json?["card"] = nil }
        let data = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data(input.utf8)
        let outcome = executor.run(name, input: data)
        if !outcome.isError, let period = ChatAgent.period(in: data) { lastPeriod = period }
        toolLog.append("\(name) \(input) -> \(outcome.json.prefix(300))")
        if let proposal = outcome.proposal { outputs.append(.proposal(proposal)) }
        if let change = outcome.change { outputs.append(.change(change)) }
        if let bill = outcome.bill { outputs.append(.bill(bill)) }
        if let chart = outcome.chart { outputs.append(.chart(chart)) }
        return outcome.json
    }

    private static func folded(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Tolerates what the small model gets wrong in a predictable way: category next to a split (the split wins).
    private static func clean(_ value: Any, code: String) -> Any {
        guard var object = convertAmounts(value, code: code) as? [String: Any] else { return value }
        if (object["split"] as? [Any])?.count ?? 0 >= 2 { object["category"] = nil }
        return object
    }

    private static func convertAmounts(_ value: Any, code: String) -> Any {
        if let array = value as? [Any] { return array.map { convertAmounts($0, code: code) } }
        guard var object = value as? [String: Any] else { return value }
        for (key, child) in object {
            if key == "amount", let text = child as? String { object[key] = amount(text, code: code).map(NSDecimalNumber.init(decimal:)) ?? text }
            else { object[key] = convertAmounts(child, code: code) }
        }
        return object
    }

    /// "28rb", "100k", "1,5jt", "2 juta", "Rp28.000", "$4.50", "4,50 €" → major units of `code`. nil when it isn't an amount.
    static func amount(_ text: String, code: String = "IDR") -> Decimal? {
        var s = text.lowercased().replacingOccurrences(of: " ", with: "")
        for affix in ["rp", code.lowercased(), Money.symbol(code).lowercased()] where !affix.isEmpty {
            if s.hasPrefix(affix) { s = String(s.dropFirst(affix.count)) }
            if s.hasSuffix(affix) { s = String(s.dropLast(affix.count)) }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for (suffix, scale) in [("ribu", 1e3), ("rb", 1e3), ("k", 1e3), ("juta", 1e6), ("jt", 1e6)] where s.hasSuffix(suffix) {
            guard let number = Decimal(string: s.dropLast(suffix.count).replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
                  number > 0 else { return nil }
            return number * Decimal(scale)
        }
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }
        // A last separator followed by one or two digits is the decimal point, where the currency has decimals;
        // every other dot or comma groups thousands ("Rp28.000", "1,234.50", "1.234,50").
        var digits = s.filter(\.isNumber)
        if Money.fractionDigits(code) > 0, let last = s.lastIndex(where: { $0 == "." || $0 == "," }), (1...2).contains(s.distance(from: last, to: s.endIndex) - 1) {
            let fraction = String(s[s.index(after: last)...])
            digits = s[..<last].filter(\.isNumber) + "." + fraction
        }
        return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The subset of JSON Schema ChatAgent.tools uses (object, array, enum, string, integer, boolean).
    /// Apple's twist: `amount` is a string the app parses, and a proposal's `category` is one of `categories`
    /// (guided generation can't invent "Subscription", so app_context needn't list them for the model to echo).
    static func schema(_ json: [String: Any], name: String, categories: [String] = []) -> DynamicGenerationSchema {
        let description = json["description"] as? String
        if let choices = json["enum"] as? [String] { return DynamicGenerationSchema(name: name, description: description, anyOf: choices) }
        switch json["type"] as? String {
        case "object":
            let required = json["required"] as? [String] ?? []
            // Required fields first so the model fills them before the optional ones.
            let properties = (json["properties"] as? [String: [String: Any]] ?? [:])
                .sorted { (required.contains($0.key) ? 0 : 1, $0.key) < (required.contains($1.key) ? 0 : 1, $1.key) }
                .map { key, value in
                    key == "category" && name.hasPrefix("propose") && !categories.isEmpty
                        ? DynamicGenerationSchema.Property(name: key, description: value["description"] as? String,
                                                           schema: DynamicGenerationSchema(name: "\(name)_\(key)", anyOf: categories),
                                                           isOptional: !required.contains(key))
                        : key == "amount"
                        ? DynamicGenerationSchema.Property(name: key, description: "As the user wrote it, e.g. 28rb, 100k, 1,5jt.",
                                                           schema: DynamicGenerationSchema(type: String.self), isOptional: !required.contains(key))
                        : DynamicGenerationSchema.Property(name: key, description: value["description"] as? String,
                                                           schema: schema(value, name: "\(name)_\(key)", categories: categories), isOptional: !required.contains(key))
                }
            return DynamicGenerationSchema(name: name, description: description, properties: properties)
        case "array": return DynamicGenerationSchema(arrayOf: schema(json["items"] as? [String: Any] ?? [:], name: "\(name)_item", categories: categories))
        case "integer": return DynamicGenerationSchema(type: Int.self)
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        default: return DynamicGenerationSchema(type: String.self)
        }
    }
}

/// One ChatAgent tool for FoundationModels: arguments arrive as generated JSON and go to ToolExecutor unchanged.
private struct ExecutorTool: Tool {
    typealias Arguments = GeneratedContent
    let name: String
    let description: String
    let parameters: GenerationSchema
    let run: @Sendable (String, String) async -> String

    func call(arguments: GeneratedContent) async throws -> String {
        await run(name, arguments.jsonString)
    }
}
