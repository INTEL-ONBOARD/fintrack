import PhotosUI
import SwiftUI

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var store: FinanceStore
    @AppStorage("monthlyEmailOptIn") private var monthlyEmailOptIn = true
    @State private var name = ""
    @State private var email = ""
    @State private var currency = "LKR"
    @State private var billAlerts = true
    @State private var monthlySummary = true
    @State private var generalAlerts = true
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Profile") {
                PhotosPicker(selection: $selectedAvatar, matching: .images) {
                    Label(isUploadingAvatar ? "Uploading avatar…" : "Choose profile avatar", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(isUploadingAvatar)
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
            Section("Email") {
                Toggle("Monthly email summary", isOn: $monthlyEmailOptIn)
                Text("You can unsubscribe from a monthly email using the link inside that email.")
                    .font(.footnote).foregroundStyle(.secondary)
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
        .onChange(of: selectedAvatar) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
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
            do {
                await store.saveSettings(value, accessToken: auth.token())
                try await auth.setMonthlyEmailPreference(optIn: monthlyEmailOptIn)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "The selected image could not be opened."
                return
            }
            guard data.count <= 2 * 1024 * 1024 else {
                errorMessage = "The avatar must be smaller than 2 MB."
                return
            }
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            guard ["image/png", "image/jpeg", "image/webp"].contains(mime) else {
                errorMessage = "Use a PNG, JPEG or WebP image."
                return
            }
            try await auth.uploadAvatar(dataURI: "data:\(mime);base64,\(data.base64EncodedString())")
        } catch { errorMessage = error.localizedDescription }
    }
}
