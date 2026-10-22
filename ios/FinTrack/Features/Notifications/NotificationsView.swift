import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @State private var deleting: FinanceNotification?

    var body: some View {
        List {
            if store.notifications.isEmpty {
                ContentUnavailableView("No notifications", systemImage: "bell", description: Text("Notifications from your FinMate account will appear here."))
            }
            ForEach(store.notifications) { notification in
                Button {
                    Task { await store.markNotificationRead(notification, accessToken: auth.token()) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: notification.read ? "bell" : "bell.badge.fill")
                            .foregroundStyle(notification.read ? .secondary : FinTrackStyle.purple)
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
        .navigationTitle("Notifications")
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
