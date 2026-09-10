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
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Book", value: model.settings.book.name)
                    LabeledContent("Currency", value: "IDR")
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.1"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "27"
                    LabeledContent("Version", value: "\(version) (\(build))")
                }
                Section {
                    Toggle("Auto switch", isOn: $model.autoAppearance)
                        .accessibilityIdentifier("autoAppearanceToggle")

                    Picker("Appearance", selection: Binding(
                        get: {
                            if model.autoAppearance {
                                return colorScheme == .dark ? AppearanceMode.dark : AppearanceMode.light
                            }
                            return model.manualAppearance
                        },
                        set: { newMode in
                            model.manualAppearance = newMode
                        }
                    )) {
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearanceModePicker")

                    Picker("Theme style", selection: Binding(
                        get: { model.visualDirection },
                        set: { newDir in
                            model.visualDirection = newDir
                        }
                    )) {
                        ForEach(BookVisualDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                    .accessibilityIdentifier("themeStylePicker")
                } header: {
                    Text("Appearance")
                } footer: {
                    if model.autoAppearance {
                        Text("monocle automatically matches your iOS system appearance.")
                    } else {
                        Text("Appearance is locked to your selection.")
                    }
                }
                Section {
                    NavigationLink("Backup & restore") { BackupView(model: model) }.accessibilityIdentifier("backupSettings")
                    NavigationLink("Categories") { CategoryManager(model: model) }.accessibilityIdentifier("manageCategories")
                    NavigationLink("App lock") { AppLockSettingsView(model: model) }.accessibilityIdentifier("appLockSettings")
                    if model.settings.book.kind == .sample {
                        NavigationLink("Start your real book") { RealBookOnboardingView(model: model) }
                            .accessibilityIdentifier("startRealBook")
                    } else {
                        NavigationLink("Rename book") { RenameBookView(model: model) }
                            .accessibilityIdentifier("renameRealBook")
                    }
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct RenameBookView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Book name", text: $name).accessibilityIdentifier("renameBookName")
        }
        .navigationTitle("Rename book").navigationBarTitleDisplayMode(.inline)
        .onAppear { name = model.settings.book.name }
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                do { try model.renameRealBook(to: name); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } }
        .alert("Could not rename book", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct RealBookOnboardingView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My expenses"
    @State private var confirm = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Book name", text: $name).accessibilityIdentifier("realBookName")
            } header: {
                Text("Your real book")
            } footer: {
                Text("This keeps your categories and settings, removes sample entries and unfinished drafts, and creates a safety backup first. It cannot happen by accident.")
            }
            Section {
                Button("Start empty real book", role: .destructive) { confirm = true }
                    .accessibilityIdentifier("confirmRealBook")
            }
        }
        .navigationTitle("Start real book").navigationBarTitleDisplayMode(.inline)
        .alert("Start an empty real book?", isPresented: $confirm) {
            Button("Start empty book", role: .destructive) {
                do { try model.startEmptyRealBook(named: name); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Sample entries and any unfinished draft will be removed. Your categories and settings stay in place, and a safety backup is created first.") }
        .alert("Could not start real book", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct AppLockSettingsView: View {
    let model: AppModel
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                if let timeout = model.settings.appLockTimeout {
                    LabeledContent { Text(timeout.title) } label: { Text("Current setting") }
                    Button("Turn off app lock", role: .destructive) { update(nil) }
                        .disabled(saving)
                } else {
                    Text("Off").foregroundStyle(.secondary)
                }
                ForEach(AppLockTimeout.allCases) { timeout in
                    Button { update(timeout) } label: {
                        HStack {
                            Text(timeout.title)
                            Spacer()
                            if timeout == model.settings.appLockTimeout { Image(systemName: "checkmark").foregroundStyle(MC.red) }
                        }
                    }
                    .disabled(saving || timeout == model.settings.appLockTimeout)
                }
            } header: {
                Text("Lock after leaving monocle")
            } footer: {
                Text("Turning this on or changing its timeout confirms your device authentication. monocle covers its interface while it is in the app switcher, then asks for Face ID or your device passcode when the timeout has elapsed.")
            }
            Section("Shortcuts") {
                Text("Both monocle Shortcuts always use the system device-authentication policy. A background text shortcut can record only after that system check; it does not unlock the app screen. Quick entry may still show this lock when monocle opens.")
            }
            if saving { HStack { Spacer(); ProgressView("Saving app lock…"); Spacer() } }
            if let error { Text(error).foregroundStyle(MC.red) }
        }
        .navigationTitle("App lock").navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ timeout: AppLockTimeout?) {
        saving = true
        Task {
            let result = await model.setAppLockTimeout(timeout)
            saving = false
            if case let .failure(error) = result { self.error = error.localizedDescription }
        }
    }
}
