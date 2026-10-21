import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    @AppStorage("biometricLockEnabled") private var deviceLockEnabled = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Your data") {
                NavigationLink { CategoriesView() } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                NavigationLink { BudgetsView() } label: {
                    Label("Budgets", systemImage: "chart.pie")
                }
                NavigationLink { ImportView() } label: {
                    Label("Import message or receipt", systemImage: "square.and.arrow.down")
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
                Text("Your transactions are stored on this device. Online sync is not connected yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .alert("Device lock", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
}
