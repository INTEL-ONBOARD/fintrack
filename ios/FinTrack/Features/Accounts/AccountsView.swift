import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @State private var showingEditor = false
    @State private var editing: FinanceAccount?
    @State private var deleting: FinanceAccount?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.accounts.isEmpty {
                    ContentUnavailableView("No accounts", systemImage: "building.columns", description: Text("Add your bank or cash accounts."))
                }
                ForEach(store.accounts) { account in
                    Button { editing = account } label: {
                        FinanceCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name).font(.headline)
                                    Text(account.bank.isEmpty ? account.type.title : "\(account.bank) · \(account.type.title)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.formatted(account.balanceMinor)).font(.headline)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { deleting = account } }
                }
                Button("Add Account", systemImage: "plus") { showingEditor = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Accounts")
        .sheet(isPresented: $showingEditor) { AccountEditorView() }
        .sheet(item: $editing) { AccountEditorView(account: $0) }
        .confirmationDialog("Delete this account?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Account", role: .destructive) {
                guard let deleting else { return }
                Task { await store.deleteAccount(deleting, accessToken: auth.token()) }
                self.deleting = nil
            }
        }
    }
}

private struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    let account: FinanceAccount?
    @State private var name: String
    @State private var type: FinanceAccountType
    @State private var balance: String
    @State private var bank: String
    @State private var errorMessage: String?

    init(account: FinanceAccount? = nil) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .checking)
        _balance = State(initialValue: account.map { NSDecimalNumber(value: $0.balanceMinor).dividing(by: 100).stringValue } ?? "")
        _bank = State(initialValue: account?.bank ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Account name", text: $name)
                Picker("Type", selection: $type) { ForEach(FinanceAccountType.allCases) { Text($0.title).tag($0) } }
                TextField("Balance in LKR", text: $balance).keyboardType(.decimalPad)
                TextField("Bank", text: $bank)
                Button("Save Account") { save() }.buttonStyle(PrimaryButtonStyle()).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            .navigationTitle(account == nil ? "Add Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .alert("Unable to save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let balanceMinor = Money.minorUnits(from: balance) else { errorMessage = "Enter a valid balance."; return }
        var value = account ?? FinanceAccount(name: name, type: type, balanceMinor: balanceMinor, bank: bank)
        value.name = name; value.type = type; value.balanceMinor = balanceMinor; value.bank = bank
        do { try store.save(value); if let token = auth.token() { Task { await store.pushAccount(value, accessToken: token) } }; dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}
