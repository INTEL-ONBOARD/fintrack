import SwiftUI

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession

    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Account action", selection: $isRegistering) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }
                    .pickerStyle(.segmented)

                    FinanceCard {
                        if isRegistering {
                            TextField("Name", text: $name)
                        }
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                        if isRegistering {
                            Text("Your password must contain at least 8 characters.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(FinTrackStyle.green)
                    }

                    Button(isRegistering ? "Create account" : "Sign in") {
                        Task { await submit() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(auth.isLoading)

                    if auth.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(FinTrackStyle.background)
            .navigationTitle(isRegistering ? "Create account" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Account", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: auth.isAuthenticated) { _, authenticated in
                if authenticated { dismiss() }
            }
        }
    }

    private func submit() async {
        message = nil
        errorMessage = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        if isRegistering {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Enter your name."
                return
            }
            guard password.count >= 8 else {
                errorMessage = "Use a password with at least 8 characters."
                return
            }
        }

        do {
            if isRegistering {
                let status = try await auth.register(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: cleanEmail,
                    password: password
                )
                message = status == "verification_sent"
                    ? "Check your email, verify the account, then sign in."
                    : "Check your email to verify the account."
                isRegistering = false
                password = ""
            } else {
                try await auth.login(email: cleanEmail, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
