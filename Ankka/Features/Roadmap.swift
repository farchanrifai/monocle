import SwiftUI

/// Settings ▸ Roadmap: what's coming, with 👍/👎 that set what gets built next, and what already shipped (struck
/// through). The list comes from the chat server (`GET /v1/roadmap`), so items change without an app release; the last
/// list is kept for offline. Counts stay on the server.
struct RoadmapItem: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let shippedIn: String?

    enum CodingKeys: String, CodingKey { case id, title, detail, shippedIn = "shipped_in" }
}

struct RoadmapView: View {
    @AppStorage("roadmapCache") private var cache = Data()
    @State private var items: [RoadmapItem] = []
    @State private var failed = false

    var body: some View {
        List {
            let coming = items.filter { $0.shippedIn == nil }
            let shipped = items.filter { $0.shippedIn != nil }
            if !coming.isEmpty {
                Section {
                    ForEach(coming) { ComingRow(item: $0) }
                } header: {
                    Text("Coming")
                } footer: {
                    Text("Vote for what you want next. Votes are anonymous and decide what gets built first.")
                }
            }
            if !shipped.isEmpty {
                Section("Shipped") {
                    ForEach(shipped) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title).strikethrough().foregroundStyle(.secondary)
                            Spacer()
                            Text(item.shippedIn ?? "").font(.footnote.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        .accessibilityLabel("\(item.title), shipped in \(item.shippedIn ?? "")")
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                if failed {
                    ContentUnavailableView("Roadmap unavailable", systemImage: "wifi.slash", description: Text("Connect to the internet to see what's coming."))
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Roadmap")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if items.isEmpty, let cached = try? JSONDecoder().decode([RoadmapItem].self, from: cache) { items = cached }
        struct Response: Decodable { let items: [RoadmapItem] }
        do {
            let (data, _) = try await URLSession.shared.data(from: WhatsNew.server.appending(path: "v1/roadmap"))
            items = try JSONDecoder().decode(Response.self, from: data).items
            cache = (try? JSONEncoder().encode(items)) ?? cache
        } catch {
            failed = true
        }
    }
}

/// Tap a thumb to vote, the other to switch, the same one again to take the vote back.
private struct ComingRow: View {
    let item: RoadmapItem
    @State private var vote: Bool?

    private var key: String { "roadmapVote.\(item.id)" }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if !item.detail.isEmpty { Text(item.detail).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            Thumbs(vote: vote) { up in
                let next: Bool? = vote == up ? nil : up
                WhatsNew.post("v1/roadmap/vote", ["id": item.id, "vote": Self.number(next), "previous": Self.number(vote)])
                vote = next
                UserDefaults.standard.set(next, forKey: key)
            }
        }
        .onAppear { vote = UserDefaults.standard.object(forKey: key) as? Bool }
    }

    private static func number(_ vote: Bool?) -> Int { vote.map { $0 ? 1 : -1 } ?? 0 }
}
