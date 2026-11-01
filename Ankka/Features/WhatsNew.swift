import SwiftUI

/// What changed in each version, newest first. Shipped inside the app, so it works offline and costs nothing.
/// Add an entry when the version goes out; a version without one shows no sheet.
enum WhatsNew {
    static let releases: [(version: String, notes: [String])] = [
        ("0.9.9", [
            "Budgets run by calendar month. A budget can repeat every month or cover just one.",
            "New Analytics tab: see any month or pick your own dates.",
            "Add an expense in any currency and see what it comes to in yours.",
            "Chat can add several expenses from one message, and learns your categories as you go.",
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
        var request = URLRequest(url: URL(string: "https://ankka-chat.farchan.workers.dev/v1/vote")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["version": version, "up": up])
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

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("What's new in Ankka \(version)").font(.title2.bold()).padding(.top, 32)
            ScrollView {
                WhatsNewNotes(version: version)
            }
            VoteRow(version: version)
            Button { dismiss() } label: { Text("Continue").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(24)
        .tint(MC.red)
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
            thumb(up: true)
            thumb(up: false)
        }
        .onAppear { vote = UserDefaults.standard.object(forKey: WhatsNew.voteKey(version)) as? Bool }
    }

    private func thumb(up: Bool) -> some View {
        Button {
            vote = up
            WhatsNew.vote(version, up: up)
        } label: {
            Image(systemName: up ? (vote == true ? "hand.thumbsup.fill" : "hand.thumbsup") : (vote == false ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                .font(.title3).frame(width: HomeMetrics.hitTarget, height: HomeMetrics.hitTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(vote == up ? MC.red : .secondary)
        .disabled(vote != nil)
        .accessibilityLabel(up ? "Like" : "Dislike")
    }
}
