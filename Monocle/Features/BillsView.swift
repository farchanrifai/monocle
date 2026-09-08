import SwiftUI

struct BillsView: View {
    @Bindable var model: AppModel
    @State private var editing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Eyebrow(text: "A little planning ahead")
                    Text("Fewer things\non your mind.").font(.largeTitle.weight(.medium)).tracking(-1)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Eyebrow(text: "Monthly / sample bill"); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary) }
                        HStack(spacing: 14) {
                            CategoryMark(symbol: "wifi")
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Home internet").font(.headline)
                                Text("Due on the 15th").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(Money.format(35_000_000)).font(.system(size: 32, weight: .medium, design: .monospaced)).tracking(-1)
                        Divider()
                        Label(model.settings.billAutomatic ? "Record automatically" : "Confirm before recording", systemImage: model.settings.billAutomatic ? "bolt" : "checkmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(22).background(MC.surface, in: RoundedRectangle(cornerRadius: 22))
                        .onTapGesture { editing = true }.accessibilityAddTraits(.isButton).accessibilityAction { editing = true }
                    RecordButton(title: "Configure sample bill", symbol: "slider.horizontal.3") { editing = true }
                    Text("Explore how each bill is handled. Scheduling and notifications are not active in this prototype; no expenses are automatically created.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(MC.paper).navigationTitle("Bills").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editing) { BillEditor(model: model) }
        }
    }
}

struct BillEditor: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var automatic = false
    @State private var reminder = true
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bill", value: "Home internet")
                    LabeledContent("Amount", value: Money.format(35_000_000))
                    LabeledContent("Schedule", value: "Monthly, day 15")
                }
                Section {
                    Picker("On the due date", selection: $automatic) {
                        Text("Keep pending until I confirm").tag(false)
                        Text("Record automatically").tag(true)
                    }.pickerStyle(.inline).labelsHidden().accessibilityIdentifier("billMode")
                } header: { Text("Recording") } footer: {
                    Text(automatic ? "An assumed expense counts toward spending. You can correct it later." : "A pending bill does not count as spending until you confirm it.")
                }
                Section { Toggle("Remind me", isOn: $reminder) } footer: { Text("Reminders are independent of recording. This prototype stores your choice; delivery comes later.") }
                if let error { Text(error).foregroundStyle(MC.red) }
            }.navigationTitle("Bill settings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                var settings = model.settings; settings.billAutomatic = automatic; settings.billReminder = reminder
                                try model.saveSettings(settings); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }.onAppear { automatic = model.settings.billAutomatic; reminder = model.settings.billReminder }
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Book", value: "Sample book")
                    LabeledContent("Currency", value: "IDR")
                    LabeledContent("Version", value: "0.1.3 · Prototype")
                }
                Section {
                    NavigationLink("Backup & restore") { BackupView(model: model) }.accessibilityIdentifier("backupSettings")
                    NavigationLink("Categories") { CategoryManager(model: model) }.accessibilityIdentifier("manageCategories")
                }
                Section("Try the flow") {
                    Text("Record a coffee with the keypad or type Coffee 28k. Tap an entry to edit, or touch and hold to repeat or delete it.")
                    Text("Your sample entries stay on this device. Interruptions preserve your draft; leaving a changed entry asks before discarding it.")
                }
                Section("Before daily use") {
                    Text("This is an interaction prototype. App lock, imports, scheduled bills, and phone update checks are still pending. Use sample purchases here.")
                }
                Section("Coming next") {
                    Label("Face ID and lock timeout", systemImage: "faceid")
                    Label("Split entry", systemImage: "square.grid.2x2")
                    Label("CSV import", systemImage: "tablecells")
                }.foregroundStyle(.secondary)
            }.navigationTitle("monocle").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
