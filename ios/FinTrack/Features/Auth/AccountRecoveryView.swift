import SwiftUI

struct AccountRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession
    @State private var mode = 0
    @State private var email = ""
    @State private var token = ""
    @State private var password = ""
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandPageIntro(title: "Account help", subtitle: "Get back to your finance data.", icon: "key")
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                Picker("Action", selection: $mode) {
                    Text("Reset password").tag(0)
                    Text("Verify email").tag(1)
                    Text("Resend verification").tag(2)
                }
                .pickerStyle(.segmented)
                if mode == 1 {
                    TextField("Verification token", text: $token)
                } else {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                if mode == 0 {
                    TextField("Reset token (optional until email arrives)", text: $token)
                    SecureField("New password", text: $password)
                    Text("Use at least 8 characters.").font(.caption).foregroundStyle(.secondary)
                }
                Button(buttonTitle) { Task { await submit() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading)
                if isLoading { ProgressView() }
                if let message { Text(message).foregroundStyle(FinTrackStyle.green) }
            }
            .finTrackGroupedScreen()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .alert("Account help", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var buttonTitle: String {
        if mode == 1 { return "Verify email" }
        if mode == 2 { return "Resend email" }
        return password.isEmpty ? "Send reset email" : "Reset password"
    }

    private func submit() async {
        message = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            if mode == 1 {
                guard !token.isEmpty else { errorMessage = "Enter the verification token."; return }
                try await auth.verifyEmail(token: token)
                message = "Email verified. You can continue in FinTrack."
            } else if mode == 2 {
                guard !email.isEmpty else { errorMessage = "Enter your email."; return }
                try await auth.resendVerification(email: email)
                message = "If the account exists, a verification email will be sent."
            } else if password.isEmpty {
                guard !email.isEmpty else { errorMessage = "Enter your email."; return }
                try await auth.requestPasswordReset(email: email)
                message = "If the account exists, reset instructions will be sent."
            } else {
                guard !token.isEmpty, password.count >= 8 else { errorMessage = "Enter the reset token and a password with at least 8 characters."; return }
                try await auth.resetPassword(token: token, newPassword: password)
                message = "Password reset. Close this screen and sign in again."
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
