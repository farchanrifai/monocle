import SwiftUI

struct BudgetsView: View {
    @Bindable var model: AppModel
    @State private var editing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Eyebrow(text: model.cycle.label)
                    Text("Room for what\nmatters.").font(.largeTitle.weight(.medium)).tracking(-1)
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: model.remaining >= 0 ? "Left this cycle" : "Over budget")
                        Text(Money.format(abs(model.remaining))).font(.system(size: 37, weight: .medium, design: .monospaced)).tracking(-1.5).minimumScaleFactor(0.6).lineLimit(1)
                        ProgressView(value: min(1, Double(model.spent) / Double(model.settings.budget))).tint(MC.red)
                        HStack {
                            Text("\(Money.format(model.spent)) spent")
                            Spacer()
                            Text("of \(Money.format(model.settings.budget))")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(22).background(MC.surface, in: RoundedRectangle(cornerRadius: 22))
                    HStack {
                        Text("Where it went").font(.title3.weight(.semibold))
                        Spacer()
                        Eyebrow(text: "This cycle")
                    }
                    VStack(spacing: 22) {
                        ForEach(model.categories) { category in
                            let spent = model.spent(in: category)
                            HStack(spacing: 14) {
                                CategoryMark(symbol: category.symbol)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(category.name).font(.subheadline)
                                        Spacer()
                                        Text(Money.format(spent)).font(.subheadline.monospacedDigit())
                                    }
                                    ProgressView(value: model.spent == 0 ? 0 : Double(spent) / Double(model.spent)).tint(.primary)
                                }
                            }
                        }
                    }
                    Text("The sample budget helps you explore the cycle view. Category limits and historical budget changes come in the budgeting milestone.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(MC.paper)
                .navigationTitle("Budgets").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit", systemImage: "slider.horizontal.3") { editing = true } } }
                .sheet(isPresented: $editing) { BudgetEditor(model: model) }
        }
    }
}

struct BudgetEditor: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var startDay = 1
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Overall budget · IDR") { TextField("4500000", text: $amount).keyboardType(.numberPad) }
                Section("Cycle starts") {
                    Picker("Day of month", selection: $startDay) { ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) } }
                    LabeledContent("Preview", value: BudgetCycle.containing(.now, startDay: startDay).label)
                }
                Section {
                    Text("This changes the sample cycle for exploration. The release version will preserve past periods and preview the transition before a start-day change.")
                        .foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(MC.red) } }
            }.navigationTitle("Sample budget").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                var settings = model.settings
                                settings.budget = try Money.parse(amount); settings.startDay = startDay
                                try model.saveSettings(settings); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                .onAppear { amount = Money.digits(model.settings.budget); startDay = model.settings.startDay }
        }
    }
}
