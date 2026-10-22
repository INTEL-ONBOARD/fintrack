import SwiftUI

struct PasswordChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            SecureField("Current password", text: $oldPassword)
            SecureField("New password", text: $newPassword)
            SecureField("Confirm new password", text: $confirmPassword)
            Button("Change Password") { Task { await save() } }
                .buttonStyle(PrimaryButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            if let message { Text(message).foregroundStyle(FinTrackStyle.green) }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        .alert("Unable to change password", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func save() async {
        guard newPassword.count >= 8 else { errorMessage = "Use a password with at least 8 characters."; return }
        guard newPassword == confirmPassword else { errorMessage = "The new passwords do not match."; return }
        do {
            try await auth.changePassword(oldPassword: oldPassword, newPassword: newPassword)
            message = "Password changed successfully."
            oldPassword = ""; newPassword = ""; confirmPassword = ""
        } catch { errorMessage = error.localizedDescription }
    }
}
