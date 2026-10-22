import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthSession
    @AppStorage("biometricLockEnabled") private var deviceLockEnabled = false
    @State private var errorMessage: String?
    @State private var showingAuth = false

    var body: some View {
        List {
            Section("Account") {
                if let user = auth.user {
                    Label(user.email, systemImage: "person.crop.circle")
                    NavigationLink { ProfileSettingsView() } label: {
                        Label("Profile settings", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink { SessionsView() } label: {
                        Label("Active sessions", systemImage: "lock.shield")
                    }
                    Button("Sign out", role: .destructive) {
                        Task { await auth.logout() }
                    }
                } else {
                    Button {
                        showingAuth = true
                    } label: {
                        Label("Sign in to sync", systemImage: "person.crop.circle.badge.plus")
                    }
                    Text("Use your FinMate account when you are ready to connect online data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Your data") {
                NavigationLink { CategoriesView() } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                NavigationLink { BudgetsView() } label: {
                    Label("Budgets", systemImage: "chart.pie")
                }
                NavigationLink { AccountsView() } label: {
                    Label("Accounts", systemImage: "building.columns")
                }
                NavigationLink { GoalsView() } label: {
                    Label("Goals", systemImage: "target")
                }
                NavigationLink { BillsView() } label: {
                    Label("Bills", systemImage: "calendar.badge.clock")
                }
                NavigationLink { NotificationsView() } label: {
                    Label("Notifications", systemImage: "bell")
                }
                NavigationLink { ImportView() } label: {
                    Label("Import message or receipt", systemImage: "square.and.arrow.down")
                }
                NavigationLink { DataManagementView() } label: {
                    Label("Data management", systemImage: "externaldrive.badge.icloud")
                }
            }

            Section("Privacy") {
                Toggle(isOn: Binding(
                    get: { deviceLockEnabled },
                    set: { enabled in
                        if enabled {
                            var authError: NSError?
                            if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
                                deviceLockEnabled = true
                            } else {
                                errorMessage = authError?.localizedDescription ?? "Set a device passcode before enabling the lock."
                            }
                        } else {
                            deviceLockEnabled = false
                        }
                    }
                )) {
                    Label("Require device unlock", systemImage: "lock.shield")
                }
                Text("Your finance data is stored on this device and syncs when you sign in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingAuth) { AuthView() }
        .alert("Device lock", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
}
