import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @State private var editing: FinanceCategory?
    @State private var adding = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                BrandPageIntro(title: "Categories", subtitle: "Organize where your money goes.", icon: "square.grid.2x2")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            ForEach([TransactionKind.expense, .income], id: \.self) { kind in
                Section(kind == .expense ? "Expense categories" : "Income categories") {
                    ForEach(store.categories.filter { $0.kind == kind }) { category in
                        Button { editing = category } label: {
                            Label(category.name, systemImage: "circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(FinTrackStyle.ink, FinTrackStyle.black)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                do {
                                    try store.delete(category)
                                    if let token = auth.token() { Task { await store.syncCategoriesBudgets(accessToken: token) } }
                                }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                }
            }
        }
        .finTrackGroupedScreen()
        .navigationTitle("Categories")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { CategoryEditorView() }
        .sheet(item: $editing) { CategoryEditorView(category: $0) }
        .alert("Category", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    let category: FinanceCategory?
    @State private var name: String
    @State private var kind: TransactionKind
    @State private var errorMessage: String?

    init(category: FinanceCategory? = nil) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: category?.kind ?? .expense)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandPageIntro(title: "Category details", subtitle: "Keep your transactions organized.", icon: "square.grid.2x2")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) {
                    Text("Expense").tag(TransactionKind.expense)
                    Text("Income").tag(TransactionKind.income)
                }
                .pickerStyle(.segmented)
                Button("Save Category") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .finTrackGroupedScreen()
            .navigationTitle(category == nil ? "Add Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .alert("Unable to save", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        let value = FinanceCategory(
            id: category?.id ?? UUID(), serverID: category?.serverID,
            name: name, kind: kind, color: category?.color ?? "#151718"
        )
        do {
            try store.save(value)
            if let token = auth.token() { Task { await store.syncCategoriesBudgets(accessToken: token) } }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
