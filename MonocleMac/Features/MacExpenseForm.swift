import AppKit
import SwiftUI

struct MacExpenseForm: View {
    @Bindable var model: AppModel
    let quickRecord: Bool
    let close: (Bool) -> Void
    @FocusState private var focus: Field?
    @State private var message: String?
    @State private var saved = false
    @State private var showDiscardConfirmation = false

    private enum Field { case amount, text, note }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.draft.editing ? "Edit expense" : quickRecord ? "Quick Record" : "New expense")
                    .font(.title2.bold())
                Text(model.draft.editing ? "Update the saved transaction" : "Record spending without leaving the keyboard")
                    .foregroundStyle(.secondary)
            }

            if model.draft.mode == .text {
                TextField("Coffee 28k", text: $model.draft.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .text)
                    .onSubmit { parseText() }
                    .accessibilityLabel("Expense description and amount")
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Card")
                    Picker("Card", selection: Binding(get: { model.draft.bookID ?? model.activeBookID }, set: { id in
                        _ = model.selectBook(id); model.draft.bookID = id
                    })) {
                        ForEach(model.books) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                }
                GridRow {
                    Text("Amount")
                    TextField("IDR amount", text: $model.draft.amount)
                        .focused($focus, equals: .amount)
                        .accessibilityIdentifier("expenseAmount")
                }
                GridRow {
                    Text("Category")
                    Picker("Category", selection: $model.draft.categoryID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(model.activeCategories) { category in
                            Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
                        }
                    }.labelsHidden()
                }
                GridRow {
                    Text("Note")
                    TextField("Optional", text: $model.draft.note)
                        .focused($focus, equals: .note)
                        .accessibilityIdentifier("expenseNote")
                }
                GridRow {
                    Text("Date")
                    DatePicker("Date", selection: $model.draft.date, displayedComponents: .date).labelsHidden()
                }
            }

            if model.draft.isSplit {
                MacSplitEditor(model: model)
            } else {
                Button("Split across categories") { model.beginSplitting() }
                    .buttonStyle(.link)
            }

            if let message { Text(message).font(.caption).foregroundStyle(saved ? .green : .red).accessibilityLabel(message) }

            Spacer(minLength: 0)
            HStack {
                Text("⌘↩ Save  •  Esc Close").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel) { requestClose() }
                    .keyboardShortcut(.cancelAction)
                Button(model.draft.editing ? "Save Changes" : "Record Expense") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("recordExpense")
                    .disabled(saved)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 460)
        .onAppear { focus = model.draft.mode == .text ? .text : .amount }
        .onChange(of: model.draft.mode) { _, mode in focus = mode == .text ? .text : .amount }
        .confirmationDialog("Keep this draft?", isPresented: $showDiscardConfirmation) {
            Button("Keep Draft and Close") { model.persistDraft(); close(false) }
            Button("Discard Draft", role: .destructive) { if model.discardDraft() { close(false) } }
            Button("Continue Editing", role: .cancel) {}
        } message: { Text("Your entered details can be kept for the next time you record an expense.") }
    }

    private func parseText() {
        do {
            let parsed = try ExpenseParser.parse(model.draft.text, categories: model.activeCategories, rules: model.settings.categoryRules)
            model.draft.amount = Money.digits(parsed.amount)
            model.draft.note = parsed.note
            model.draft.categoryID = parsed.categoryID
            model.draft.source = "text"
            if parsed.categoryID == nil { message = "Amount found. Choose a category." }
        } catch { message = error.localizedDescription }
    }

    private func save() {
        if model.draft.mode == .text { parseText() }
        guard model.saveDraft() else { message = model.error; return }
        saved = true
        message = "Expense recorded"
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            close(true)
        }
    }

    private func requestClose() {
        if model.draftNeedsConfirmation { showDiscardConfirmation = true }
        else { close(false) }
    }
}

private struct MacSplitEditor: View {
    @Bindable var model: AppModel

    var body: some View {
        GroupBox("Split") {
            VStack(spacing: 8) {
                ForEach($model.draft.splitAllocations) { $allocation in
                    HStack {
                        Picker("Category", selection: $allocation.categoryID) {
                            ForEach(model.activeCategories) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                        }
                        TextField("Amount", text: $allocation.amount).frame(width: 130)
                        Button(role: .destructive) {
                            model.draft.splitAllocations.removeAll { $0.id == allocation.id }
                            if model.draft.splitAllocations.count < 2 { model.stopSplitting() }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).accessibilityLabel("Remove split")
                    }
                }
                HStack {
                    Button("Add Split") { model.addSplitAllocation() }
                    Spacer()
                    Button("Stop Splitting") { model.stopSplitting() }
                }
            }.padding(4)
        }
    }
}

@MainActor
final class QuickRecordPanelController: NSObject, NSWindowDelegate {
    private unowned let state: MacAppState
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private var closingFromForm = false

    init(state: MacAppState) { self.state = state }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
        let panel = panel ?? makePanel()
        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        if let scheme = state.model.preferredColorScheme {
            panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        } else {
            panel.appearance = nil
        }
        panel.contentViewController = NSHostingController(rootView:
            MacExpenseForm(model: state.model, quickRecord: true) { [weak self] saved in self?.finish(saved: saved) }
                .preferredColorScheme(state.model.preferredColorScheme)
        )
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let value = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        value.title = "Quick Record"
        value.level = .floating
        value.isReleasedWhenClosed = false
        value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        value.delegate = self
        panel = value
        return value
    }

    private func finish(saved: Bool) {
        closingFromForm = true
        panel?.orderOut(nil)
        closingFromForm = false
        restorePreviousApplication()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !closingFromForm { state.model.persistDraft() }
        restorePreviousApplication()
        return true
    }

    private func restorePreviousApplication() {
        previousApp?.activate(options: [])
        previousApp = nil
    }
}
