import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var pushService: PushNotificationService
    @State private var deleting: FinanceNotification?
    @State private var alertMessage: String?

    var body: some View {
        List {
            Section {
                BrandPageIntro(title: "Notifications", subtitle: "Updates that deserve your attention.", icon: "bell")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section("Device alerts") {
                Button("Enable alerts on this iPhone", systemImage: "bell.badge") {
                    Task {
                        let allowed = await pushService.requestPermissionAndRegister()
                        alertMessage = allowed
                            ? (pushService.supportsRemoteNotifications
                                ? "Alerts are allowed. FinTrack will register this device when available."
                                : "Local alerts are allowed. Push delivery needs a build signed for Push Notifications.")
                            : "Alerts are off. You can turn them on in iPhone Settings."
                    }
                }
                if let alertMessage {
                    Text(alertMessage).font(.footnote).foregroundStyle(.secondary)
                }
                if let error = pushService.registrationError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if store.notifications.isEmpty {
                ContentUnavailableView("No notifications", systemImage: "bell", description: Text("Notifications from your FinMate account will appear here."))
            }
            ForEach(store.notifications) { notification in
                Button {
                    Task { await store.markNotificationRead(notification, accessToken: auth.token()) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: notification.read ? "bell" : "bell.badge.fill")
                            .foregroundStyle(notification.read ? .secondary : FinTrackStyle.black)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notification.title).font(.headline)
                            Text(notification.body).font(.subheadline).foregroundStyle(.secondary)
                            if !notification.time.isEmpty { Text(notification.time).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .opacity(notification.read ? 0.65 : 1)
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { deleting = notification } }
            }
        }
        .finTrackGroupedScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") { Task { await store.markAllNotificationsRead(accessToken: auth.token()) } }
                    .disabled(!store.notifications.contains(where: { !$0.read }))
            }
        }
        .confirmationDialog("Delete this notification?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Notification", role: .destructive) {
                guard let deleting else { return }
                Task { await store.deleteNotification(deleting, accessToken: auth.token()) }
                self.deleting = nil
            }
        }
    }
}
