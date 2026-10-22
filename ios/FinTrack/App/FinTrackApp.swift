import LocalAuthentication
import SwiftUI

@main
struct FinTrackApp: App {
    @StateObject private var store = FinanceStore()
    @StateObject private var auth = AuthSession()
    @StateObject private var realtime = RealtimeSyncService()

    var body: some Scene {
        WindowGroup {
            FinTrackRootView()
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(realtime)
                .tint(FinTrackStyle.purple)
                .task { await auth.restore() }
        }
    }
}

private struct FinTrackRootView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var realtime: RealtimeSyncService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("biometricLockEnabled") private var deviceLockEnabled = false
    @State private var isLocked = UserDefaults.standard.bool(forKey: "biometricLockEnabled")
    @State private var lockError: String?
    @State private var reviewDraft: FinanceTransaction?
    @State private var reviewWarning: String?
    @State private var pendingShortcut: PendingShortcutDraft?
    @State private var linkMessage: String?
    @State private var showingAuth = false

    var body: some View {
        Group {
            if isLocked {
                lockView
            } else if !hasSeenWelcome {
                welcomeView
            } else {
                MainTabView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && deviceLockEnabled {
                if let reviewDraft {
                    pendingShortcut = PendingShortcutDraft(transaction: reviewDraft, reviewWarning: reviewWarning)
                    self.reviewDraft = nil
                }
                isLocked = true
            }
            if phase == .active && isLocked { Task { await unlock() } }
        }
        .task {
            if deviceLockEnabled { isLocked = true; await unlock() }
        }
        .task(id: auth.isAuthenticated) {
            guard auth.isAuthenticated, let token = auth.token() else { return }
            await store.syncAll(accessToken: token)
        }
        .task(id: auth.isAuthenticated) {
            guard auth.isAuthenticated, let token = auth.token() else {
                realtime.stop()
                return
            }
            for await event in realtime.stream(accessToken: token) {
                switch event {
                case .transactions:
                    await store.syncTransactions(accessToken: token)
                case .settings:
                    await store.syncSettings(accessToken: token)
                case .goals, .bills, .accounts, .notifications:
                    await store.syncResources(accessToken: token)
                case .unknown:
                    break
                }
            }
        }
        .onOpenURL(perform: handleShortcutURL)
        .onChange(of: auth.isAuthenticated) { _, authenticated in
            if authenticated { hasSeenWelcome = true }
        }
        .onChange(of: isLocked) { _, locked in
            if !locked { presentPendingShortcutIfReady() }
        }
        .sheet(isPresented: $showingAuth) { AuthView() }
        .sheet(item: $reviewDraft) {
            TransactionEditorView(transaction: $0, isReviewDraft: true, reviewWarning: reviewWarning)
        }
        .alert("FinTrack", isPresented: Binding(
            get: { linkMessage != nil || store.errorMessage != nil },
            set: { if !$0 { linkMessage = nil; store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: {
            Text(linkMessage ?? store.errorMessage ?? "")
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 62))
                .foregroundStyle(FinTrackStyle.purple)
            Text("FinTrack")
                .font(.largeTitle.bold())
                .foregroundStyle(FinTrackStyle.ink)
            Text("Keep your spending, income and budgets together. Start on this device, even when you’re offline.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button("Sign in to sync") {
                showingAuth = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            Button("Continue offline") {
                hasSeenWelcome = true
                presentPendingShortcutIfReady()
            }
            .padding(.bottom, 30)
        }
        .background(FinTrackStyle.background)
    }

    private var lockView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(FinTrackStyle.purple)
            Text("FinTrack is locked").font(.title2.bold())
            if let lockError { Text(lockError).foregroundStyle(.secondary) }
            Button("Unlock") { Task { await unlock() } }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
        }
    }

    private func unlock() async {
        let context = LAContext()
        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: "Unlock your finance data"
            ) else { return }
            isLocked = false
            lockError = nil
            presentPendingShortcutIfReady()
        } catch { lockError = error.localizedDescription }
    }

    private func handleShortcutURL(_ url: URL) {
        guard url.scheme == "fintrack", ["add", "import"].contains(url.host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.count == 1,
              components.queryItems?.first?.name == "id",
              let value = components.queryItems?.first?.value,
              let id = UUID(uuidString: value),
              let pending = ShortcutDraftInbox.shared.take(id: id) else {
            linkMessage = "The Shortcut draft is no longer available. Run the Shortcut again."
            return
        }
        guard pending.transaction.amountMinor > 0,
              (url.host == "import" ? pending.transaction.source == .sms : pending.transaction.source == .siri) else {
            linkMessage = "The Shortcut draft is invalid. Run the Shortcut again."
            return
        }
        if let reference = pending.transaction.externalReference,
           store.transactions.contains(where: { $0.externalReference == reference }) {
            linkMessage = "This message has already been imported."
            return
        }
        pendingShortcut = pending
        presentPendingShortcutIfReady()
    }

    private func presentPendingShortcutIfReady() {
        guard !isLocked, hasSeenWelcome, let pendingShortcut else { return }
        reviewWarning = pendingShortcut.reviewWarning
        reviewDraft = pendingShortcut.transaction
        self.pendingShortcut = nil
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { OverviewView() }
                .tabItem { Label("Overview", systemImage: "square.grid.2x2") }
            NavigationStack { TransactionsView() }
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            NavigationStack { ReportsView() }
                .tabItem { Label("Reports", systemImage: "chart.bar") }
            NavigationStack { SpendingMapView() }
                .tabItem { Label("Map", systemImage: "map") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
