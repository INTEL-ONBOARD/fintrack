import SwiftUI

struct GoalsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @State private var showingEditor = false
    @State private var editing: FinanceGoal?
    @State private var deleting: FinanceGoal?

    var body: some View {
        ScrollView {
                BrandPageIntro(title: "Goals", subtitle: "Make progress on what matters.", icon: "target")

            VStack(alignment: .leading, spacing: 14) {
                if store.goals.isEmpty { ContentUnavailableView("No goals", systemImage: "target", description: Text("Create a savings goal to track progress.")) }
                ForEach(store.goals) { goal in
                    Button { editing = goal } label: {
                        FinanceCard {
                            HStack {
                                Image(systemName: goal.icon).foregroundStyle(FinTrackStyle.black)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(goal.name).font(.headline)
                                    ProgressView(value: Double(goal.currentMinor), total: Double(max(goal.targetMinor, 1))).tint(FinTrackStyle.black)
                                    Text("\(Money.formatted(goal.currentMinor)) of \(Money.formatted(goal.targetMinor))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.buttonStyle(.plain).contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { deleting = goal } }
                }
                Button("Add Goal", systemImage: "plus") { showingEditor = true }.buttonStyle(PrimaryButtonStyle())
            }.padding(16)
        }
        .background(FinTrackStyle.background)
        .finTrackGroupedScreen()
        .navigationTitle("Goals")
        .sheet(isPresented: $showingEditor) { GoalEditorView() }
        .sheet(item: $editing) { GoalEditorView(goal: $0) }
        .confirmationDialog("Delete this goal?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Goal", role: .destructive) { guard let deleting else { return }; Task { await store.deleteGoal(deleting, accessToken: auth.token()) }; self.deleting = nil }
        }
    }
}

private struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    let goal: FinanceGoal?
    @State private var name: String
    @State private var target: String
    @State private var current: String
    @State private var icon: String
    @State private var deadline: String
    @State private var errorMessage: String?

    init(goal: FinanceGoal? = nil) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _target = State(initialValue: goal.map { NSDecimalNumber(value: $0.targetMinor).dividing(by: 100).stringValue } ?? "")
        _current = State(initialValue: goal.map { NSDecimalNumber(value: $0.currentMinor).dividing(by: 100).stringValue } ?? "")
        _icon = State(initialValue: goal?.icon ?? "target")
        _deadline = State(initialValue: goal?.deadline ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandPageIntro(title: "Goal details", subtitle: "Plan your next milestone.", icon: "target")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                TextField("Goal name", text: $name)
                TextField("Target in LKR", text: $target).keyboardType(.decimalPad)
                TextField("Current amount in LKR", text: $current).keyboardType(.decimalPad)
                TextField("SF Symbol", text: $icon)
                TextField("Deadline", text: $deadline)
                Button("Save Goal") { save() }.buttonStyle(PrimaryButtonStyle()).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            .finTrackGroupedScreen()
            .navigationTitle(goal == nil ? "Add Goal" : "Edit Goal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .alert("Unable to save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let targetMinor = Money.minorUnits(from: target), let currentMinor = Money.minorUnits(from: current.isEmpty ? "0" : current) else { errorMessage = "Enter valid goal amounts."; return }
        var value = goal ?? FinanceGoal(name: name, targetMinor: targetMinor)
        value.name = name; value.targetMinor = targetMinor; value.currentMinor = currentMinor; value.icon = icon.isEmpty ? "target" : icon; value.deadline = deadline
        do { try store.save(value); if let token = auth.token() { Task { await store.pushGoal(value, accessToken: token) } }; dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}
