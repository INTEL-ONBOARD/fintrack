import LocalAuthentication
import SwiftUI
import UIKit

enum WidgetQuickAddLink {
    static func kind(from url: URL) -> TransactionKind? {
        guard url.scheme == "fintrack", url.host == "quick-add",
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              query.count == 1, query[0].name == "kind",
              let value = query[0].value,
              let kind = TransactionKind(rawValue: value),
              kind == .expense || kind == .income else { return nil }
        return kind
    }
}

@main
struct FinTrackApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationService.self) private var pushService
    @StateObject private var store = FinanceStore()
    @StateObject private var auth = AuthSession()
    @StateObject private var realtime = RealtimeSyncService()

    var body: some Scene {
        WindowGroup {
            FinTrackRootView(pushService: pushService)
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(realtime)
                .environmentObject(pushService)
                .tint(FinTrackStyle.black)
                .task { await auth.restore() }
        }
    }
}

private struct FinTrackRootView: View {
    @ObservedObject private var pushService: PushNotificationService
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
    @State private var quickAddKind: TransactionKind?
    @State private var pendingQuickAddKind: TransactionKind?
    @State private var pendingShortcut: PendingShortcutDraft?
    @State private var linkMessage: String?
    @State private var showingAuth = false
    @State private var showingLaunchIntro = true
    @State private var lastRegisteredDeviceToken: String?
    @ScaledMetric(relativeTo: .largeTitle) private var welcomeTitleSize: CGFloat = 43

    init(pushService: PushNotificationService) {
        _pushService = ObservedObject(wrappedValue: pushService)
    }

    var body: some View {
        Group {
            if showingLaunchIntro {
                launchIntroView
            } else if isLocked {
                lockView
            } else if !hasSeenWelcome {
                welcomeView
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(showingLaunchIntro || isLocked || !hasSeenWelcome ? .dark : .light)
        .animation(.easeOut(duration: 0.25), value: showingLaunchIntro)
        .task {
            try? await Task.sleep(for: .milliseconds(1100))
            showingLaunchIntro = false
            if isLocked { await unlock() }
            else { presentPendingShortcutIfReady() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && deviceLockEnabled {
                if let reviewDraft {
                    pendingShortcut = PendingShortcutDraft(transaction: reviewDraft, reviewWarning: reviewWarning)
                    self.reviewDraft = nil
                }
                isLocked = true
            }
            if phase == .active && isLocked && !showingLaunchIntro { Task { await unlock() } }
            if phase == .active {
                Task {
                    await scheduleLocalSummaryNotification()
                    await scheduleSmartAlerts()
                }
            }
        }
        .task {
            await pushService.registerIfAuthorized()
            await scheduleLocalSummaryNotification()
            await scheduleSmartAlerts()
            refreshWidget()
        }
        .onReceive(NotificationCenter.default.publisher(for: .finTrackPushReceived)) { notification in
            guard let payload = notification.userInfo?["payload"] as? PushNotificationPayload else { return }
            do {
                try store.savePushNotification(payload)
            } catch {
                store.errorMessage = "The push notification could not be saved: \(error.localizedDescription)"
            }
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
                case .categories, .budgets:
                    await store.syncCategoriesBudgets(accessToken: token)
                case .settings:
                    await store.syncSettings(accessToken: token)
                case .goals, .bills, .accounts, .notifications:
                    await store.syncResources(accessToken: token)
                case .unknown:
                    break
                }
            }
        }
        .task(id: "\(auth.isAuthenticated)-\(pushService.deviceToken ?? "")") {
            await registerDeviceTokenIfConfigured()
        }
        .onOpenURL(perform: handleShortcutURL)
        .onChange(of: auth.isAuthenticated) { _, authenticated in
            if authenticated { hasSeenWelcome = true }
        }
        .onChange(of: hasSeenWelcome) { _, _ in presentPendingShortcutIfReady() }
        .onChange(of: store.transactions) { _, _ in
            Task {
                await scheduleLocalSummaryNotification()
                await scheduleSmartAlerts()
            }
            refreshWidget()
        }
        .onChange(of: store.budgets) { _, _ in
            Task { await scheduleSmartAlerts() }
            refreshWidget()
        }
        .onChange(of: store.settings) { _, _ in
            Task { await scheduleSmartAlerts() }
            refreshWidget()
        }
        .onChange(of: isLocked) { _, locked in
            if !locked { presentPendingShortcutIfReady() }
        }
        .sheet(isPresented: $showingAuth) { AuthView().preferredColorScheme(.light) }
        .sheet(item: $reviewDraft) {
            TransactionEditorView(transaction: $0, isReviewDraft: true, reviewWarning: reviewWarning)
        }
        .sheet(item: $quickAddKind) { kind in
            TransactionEditorView(initialKind: kind)
        }
        .alert("FinTrack", isPresented: Binding(
            get: { linkMessage != nil || store.errorMessage != nil },
            set: { if !$0 { linkMessage = nil; store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: {
            Text(linkMessage ?? store.errorMessage ?? "")
        }
    }

    private var launchIntroView: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(.white)
                .frame(width: 42, height: 3)
                .padding(.bottom, 6)
            Text("FinTrack")
                .font(.system(size: 43, weight: .regular, design: .serif))
                .foregroundStyle(.white)
            Text("YOUR MONEY, IN FOCUS")
                .font(.caption2.weight(.medium))
                .tracking(2.1)
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinTrackStyle.black.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FinTrack is opening")
    }

    private var welcomeView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let path = Bundle.main.path(forResource: "WelcomeArtwork", ofType: "png"),
                       let artwork = UIImage(contentsOfFile: path) {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(height: max(290, geometry.size.height * 0.58))
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                    }

                    Text("Money in focus.\nLife in motion.")
                        .font(.system(size: welcomeTitleSize, weight: .regular, design: .serif))
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white)
                        .padding(.top, 28)

                    Text("A clearer view of your spending, income, and the places behind every transaction.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 12)

                    Spacer(minLength: 26)

                    Button { showingAuth = true } label: {
                        HStack {
                            Text("Sign in to sync")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .overlay(Capsule().stroke(.white.opacity(0.35)))
                    }

                    Button("Continue offline") {
                        hasSeenWelcome = true
                        presentPendingShortcutIfReady()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.top, 8)
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(.black)
    }

    private var lockView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .overlay(Circle().stroke(.white.opacity(0.35)))
            Text("Your money,\njust for you.")
                .font(.system(size: 42, design: .serif))
                .foregroundStyle(.white)
            Text(lockError ?? "Unlock FinTrack to see your private finance data.")
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button("Unlock FinTrack") { Task { await unlock() } }
                .buttonStyle(OutlineButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(FinTrackStyle.black)
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
        if url.host == "quick-add" {
            guard let kind = WidgetQuickAddLink.kind(from: url) else {
                linkMessage = "This widget action is invalid. Open FinTrack to add a transaction."
                return
            }
            pendingQuickAddKind = kind
            presentPendingShortcutIfReady()
            return
        }
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
        guard !isLocked, !showingLaunchIntro, hasSeenWelcome else { return }
        if let pendingQuickAddKind {
            quickAddKind = pendingQuickAddKind
            self.pendingQuickAddKind = nil
            return
        }
        guard let pendingShortcut else { return }
        reviewWarning = pendingShortcut.reviewWarning
        reviewDraft = pendingShortcut.transaction
        self.pendingShortcut = nil
    }

    private func scheduleLocalSummaryNotification() async {
        await LocalSummaryNotificationScheduler.scheduleCurrentMonthSummary(
            transactions: store.transactions,
            categories: store.categories,
            budgets: store.budgets,
            currency: store.settings.currency
        )
    }

    private func scheduleSmartAlerts() async {
        await LocalSmartNotificationScheduler.schedule(
            transactions: store.transactions, categories: store.categories,
            budgets: store.budgets, currency: store.settings.currency
        )
    }

    private func refreshWidget() {
        WidgetSnapshotWriter.update(
            transactions: store.transactions,
            budgets: store.budgets,
            settings: store.settings
        )
    }

    private func registerDeviceTokenIfConfigured() async {
        guard auth.isAuthenticated,
              let accessToken = auth.token(),
              let deviceToken = pushService.deviceToken,
              deviceToken != lastRegisteredDeviceToken,
              let path = Bundle.main.object(forInfoDictionaryKey: "APNsDeviceTokenRegistrationPath") as? String,
              !path.isEmpty else { return }

        do {
            try await FinMateAPIClient().registerDeviceToken(
                deviceToken,
                path: path,
                accessToken: accessToken
            )
            lastRegisteredDeviceToken = deviceToken
        } catch {
            // The registration path is optional until the backend route is deployed.
        }
    }
}

private enum MainTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case transactions = "Activity"
    case reports = "Reports"
    case map = "Map"
    case settings = "Settings"

    var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "house.fill"
        case .transactions: "list.bullet"
        case .reports: "chart.bar.fill"
        case .map: "map.fill"
        case .settings: "gearshape.fill"
        }
    }
}

private struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: MainTab = .overview

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List {
                        ForEach(MainTab.allCases) { tab in
                            Button { selected = tab } label: {
                                Label(tab.rawValue, systemImage: tab.icon)
                                    .foregroundStyle(selected == tab ? FinTrackStyle.ink : FinTrackStyle.muted)
                            }
                            .listRowBackground(selected == tab ? FinTrackStyle.border : Color.clear)
                        }
                    }
                    .navigationTitle("FinTrack")
                    .finTrackGroupedScreen()
                } detail: {
                    selectedView
                }
            } else {
                selectedView
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(MainTab.allCases) { tab in
                                Button { selected = tab } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: tab.icon)
                                            .font(.system(size: 17, weight: .semibold))
                                        Text(tab.rawValue)
                                            .font(.caption2.weight(.medium))
                                    }
                                    .foregroundStyle(selected == tab ? .white : .white.opacity(0.48))
                                    .frame(maxWidth: .infinity, minHeight: 47)
                                }
                                .accessibilityAddTraits(selected == tab ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(FinTrackStyle.black, in: Capsule())
                        .padding(.horizontal, 38)
                        .padding(.bottom, 5)
                        .background(.clear)
                    }
            }
        }
    }

    @ViewBuilder private var selectedView: some View {
        switch selected {
        case .overview: NavigationStack { OverviewView() }
        case .transactions: NavigationStack { TransactionsView() }
        case .reports: NavigationStack { ReportsView() }
        case .map: NavigationStack { SpendingMapView() }
        case .settings: NavigationStack { SettingsView() }
        }
    }
}
