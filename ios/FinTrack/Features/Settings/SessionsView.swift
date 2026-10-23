import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var auth: AuthSession
    @State private var sessions: [RemoteSession] = []
    @State private var revoking: RemoteSession?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                BrandPageIntro(title: "Sessions", subtitle: "See where your account is signed in.", icon: "lock.shield")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if isLoading {
                ProgressView("Loading sessions...")
            } else if sessions.isEmpty {
                ContentUnavailableView("No active sessions", systemImage: "checkmark.shield", description: Text("Sign in again to create a session."))
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: session.sessionId == auth.currentSessionID ? "iphone" : "desktopcomputer")
                        Text(session.deviceLabel ?? "Unknown device").font(.headline)
                        if session.sessionId == auth.currentSessionID {
                            Text("This device").font(.caption).foregroundStyle(FinTrackStyle.black)
                        }
                    }
                    if let lastActiveAt = session.lastActiveAt { Text("Last active: \(lastActiveAt)").font(.caption).foregroundStyle(.secondary) }
                    Button("Revoke session", role: .destructive) { revoking = session }
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .finTrackGroupedScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Revoke this session?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })) {
            Button("Revoke", role: .destructive) {
                guard let revoking else { return }
                Task {
                    do { try await auth.revokeSession(revoking); await load() }
                    catch { errorMessage = error.localizedDescription }
                }
                self.revoking = nil
            }
        }
        .alert("Unable to load sessions", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { sessions = try await auth.sessions().filter { $0.sessionId != nil } }
        catch { errorMessage = error.localizedDescription }
    }
}
