import SwiftUI

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var store: FinanceStore
    @State private var name = ""
    @State private var email = ""
    @State private var currency = "LKR"
    @State private var billAlerts = true
    @State private var monthlySummary = true
    @State private var generalAlerts = true
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                TextField("Currency", text: $currency)
                    .textInputAutocapitalization(.characters)
            }
            Section("Notifications") {
                Toggle("Bill alerts", isOn: $billAlerts)
                Toggle("Monthly summary", isOn: $monthlySummary)
                Toggle("General alerts", isOn: $generalAlerts)
            }
            NavigationLink { PasswordChangeView() } label: {
                Label("Change password", systemImage: "key")
            }
            Button("Save Settings") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Profile Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        .onAppear { load() }
        .alert("Unable to save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func load() {
        let value = store.settings
        name = value.name.isEmpty ? (auth.user?.name ?? "") : value.name
        email = value.email.isEmpty ? (auth.user?.email ?? "") : value.email
        currency = value.currency
        billAlerts = value.notifications["billAlerts"] ?? true
        monthlySummary = value.notifications["monthlySummary"] ?? true
        generalAlerts = value.notifications["generalAlerts"] ?? true
    }

    private func save() {
        guard !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a currency code."
            return
        }
        let value = FinanceUserSettings(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
            notifications: [
                "billAlerts": billAlerts,
                "monthlySummary": monthlySummary,
                "generalAlerts": generalAlerts
            ]
        )
        Task {
            await store.saveSettings(value, accessToken: auth.token())
            dismiss()
        }
    }
}
