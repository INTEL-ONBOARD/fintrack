import SwiftUI

struct DataManagementView: View {
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var store: FinanceStore
    @State private var showingRemoteConfirmation = false
    @State private var showingLocalConfirmation = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        Form {
                Section {
                    BrandPageIntro(title: "Your data", subtitle: "Manage information on this device and in your account.", icon: "externaldrive")
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            Section("Local data") {
                Text("Remove transactions, categories, budgets, accounts, goals, bills and notifications from this device.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Delete local data", role: .destructive) { showingLocalConfirmation = true }
                    .disabled(isWorking)
            }
            Section("Cloud data") {
                Text("This removes your synced finance data and active sessions from FinMate. Your account remains available.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Delete all cloud data", role: .destructive) { showingRemoteConfirmation = true }
                    .disabled(!auth.isAuthenticated || isWorking)
            }
            if isWorking { ProgressView("Working…") }
            if let message { Text(message).foregroundStyle(FinTrackStyle.green) }
        }
        .finTrackGroupedScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Delete all cloud data?", isPresented: $showingRemoteConfirmation) {
            Button("Delete Cloud Data", role: .destructive) { Task { await deleteCloudData() } }
        } message: {
            Text("This cannot be undone. Your account will be signed out after the deletion.")
        }
        .confirmationDialog("Delete local data?", isPresented: $showingLocalConfirmation) {
            Button("Delete Local Data", role: .destructive) { deleteLocalData() }
        } message: {
            Text("This removes all finance records stored on this device.")
        }
        .alert("Data management", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func deleteLocalData() {
        do {
            try store.deleteAllLocalData()
            message = "Local finance data was deleted."
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteCloudData() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.deleteUserData()
            try store.deleteAllLocalData()
            message = "Cloud and local finance data were deleted."
        } catch { errorMessage = error.localizedDescription }
    }
}
