import SwiftUI

/// What changed in each version, newest first. Shipped inside the app, so it works offline and costs nothing.
/// Add an entry when the version goes out; a version without one shows no sheet.
enum WhatsNew {
    static let releases: [(version: String, notes: [String])] = [
        ("1.0.0", [
            "Welcome to Ankka 1.0. Make a card for every purpose: everyday spending, a trip, a project.",
            "Monthly budgets, recurring bills and Analytics, with expenses in any currency.",
            "Ask Ankka in chat: add expenses in plain words, or ask where your money goes.",
        ]),
    ]

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// The version to announce on launch, if any: notes exist for it and this install hasn't seen them. A new install
    /// (`isNewUser`) gets onboarding instead.
    static func versionToShow(current: String, lastSeen: String, isNewUser: Bool) -> String? {
        guard !isNewUser, current != lastSeen, releases.contains(where: { $0.version == current }) else { return nil }
        return current
    }

    /// One anonymous 👍/👎 per version, counted by the chat server (no device id). Fire and forget.
    static func vote(_ version: String, up: Bool) {
        UserDefaults.standard.set(up, forKey: voteKey(version))
        post("v1/vote", ["version": version, "up": up])
    }

    /// The chat server (server/ankka-chat), which also counts What's New and Roadmap votes.
    static let server: URL = {
        #if DEBUG
        // `-ankkaServer http://localhost:8787/` points a simulator run at `wrangler dev`.
        if let url = UserDefaults.standard.string(forKey: "ankkaServer").flatMap(URL.init(string:)) { return url }
        #endif
        return URL(string: "https://ankka-chat.farchan.workers.dev/")!
    }()

    static func post(_ path: String, _ body: [String: Any]) {
        var request = URLRequest(url: server.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    static func voteKey(_ version: String) -> String { "whatsNewVote.\(version)" }
}

/// Shows the sheet once, the first launch after an update.
struct WhatsNewPrompt: ViewModifier {
    let model: AppModel
    @AppStorage("whatsNewSeenVersion") private var seen = ""
    @State private var version: String?

    func body(content: Content) -> some View {
        content
            .onAppear {
                let current = WhatsNew.currentVersion
                guard ProcessInfo.processInfo.environment["ANKKA_TEST_RUN"] == nil else { return } // UI tests and screenshots
                version = WhatsNew.versionToShow(current: current, lastSeen: seen, isNewUser: model.showOnboarding)
                seen = current
            }
            .sheet(item: Binding(get: { version.map(Announced.init) }, set: { version = $0?.id })) { item in
                WhatsNewSheet(version: item.id)
            }
    }

    private struct Announced: Identifiable { let id: String }
}

struct WhatsNewSheet: View {
    let version: String
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 420

    // Sized to its content so it stays a floating (glass) sheet; past the screen it opens full height and scrolls.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What's new in Ankka \(version)").font(.title2.bold()).padding(.top, 8)
                WhatsNewNotes(version: version)
                VoteRow(version: version)
                Button { dismiss() } label: { Text("Continue").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .tint(MC.red)
        .presentationDetents([.height(height)])
    }
}

/// Every version's notes, for Settings ▸ What's new.
struct WhatsNewHistoryView: View {
    var body: some View {
        List(WhatsNew.releases, id: \.version) { release in
            Section("Ankka \(release.version)") {
                WhatsNewNotes(version: release.version)
                VoteRow(version: release.version)
            }
        }
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WhatsNewNotes: View {
    let version: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WhatsNew.releases.first { $0.version == version }?.notes ?? [], id: \.self) { note in
                Label { Text(note) } icon: { Image(systemName: "sparkle").foregroundStyle(MC.red) }
            }
        }
    }
}

/// "Like this update?" with 👍/👎; after a vote it thanks and stays put (one vote per version).
private struct VoteRow: View {
    let version: String
    @State private var vote: Bool?

    var body: some View {
        HStack {
            Text(vote == nil ? "Like this update?" : "Thanks for telling us").foregroundStyle(.secondary)
            Spacer()
            Thumbs(vote: vote) { up in
                vote = up
                WhatsNew.vote(version, up: up)
            }
            .disabled(vote != nil)
        }
        .onAppear { vote = UserDefaults.standard.object(forKey: WhatsNew.voteKey(version)) as? Bool }
    }
}

/// 👍 and 👎, the chosen one filled in red. `vote`: true up, false down, nil none.
struct Thumbs: View {
    let vote: Bool?
    let tap: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            thumb(up: true)
            thumb(up: false)
        }
    }

    private func thumb(up: Bool) -> some View {
        Button { tap(up) } label: {
            Image(systemName: "hand.thumbs\(up ? "up" : "down")\(vote == up ? ".fill" : "")")
                .font(.title3).frame(width: HomeMetrics.hitTarget, height: HomeMetrics.hitTarget)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(vote == up ? MC.red : .secondary)
        .accessibilityLabel(up ? "Like" : "Dislike")
        .accessibilityAddTraits(vote == up ? .isSelected : [])
    }
}
