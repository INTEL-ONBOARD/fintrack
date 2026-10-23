import Combine
import UIKit
import UserNotifications

extension Notification.Name {
    static let finTrackPushReceived = Notification.Name("finTrackPushReceived")
}

struct PushNotificationPayload: Equatable {
    let id: String?
    let title: String
    let body: String
    let time: String
    let type: FinanceNotificationType

    init(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        let alertText = aps?["alert"] as? String
        let data = userInfo["data"] as? [String: Any] ?? [:]

        id = Self.stringValue(data["id"] ?? userInfo["id"])
        title = Self.stringValue(data["title"] ?? alert?["title"] ?? userInfo["title"]) ?? "FinTrack notification"
        body = Self.stringValue(data["body"] ?? alert?["body"] ?? userInfo["body"]) ?? alertText ?? "You have a new notification."
        time = Self.stringValue(data["time"] ?? userInfo["time"]) ?? ""
        type = FinanceNotificationType(rawValue: Self.stringValue(data["type"] ?? userInfo["type"]) ?? "") ?? .info
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}

final class PushNotificationService: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    static let deviceTokenKey = "fintrack.apns.device-token"

    @Published private(set) var deviceToken: String?
    @Published private(set) var registrationError: String?

    var supportsRemoteNotifications: Bool {
        Bundle.main.object(forInfoDictionaryKey: "RemoteNotificationsAvailable") as? Bool ?? true
    }

    override init() {
        deviceToken = UserDefaults.standard.string(forKey: Self.deviceTokenKey)
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    @MainActor
    func registerIfAuthorized() async {
        guard supportsRemoteNotifications else {
            registrationError = nil
            return
        }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    @MainActor
    func requestPermissionAndRegister() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        if supportsRemoteNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = Self.tokenString(from: deviceToken)
        self.deviceToken = token
        UserDefaults.standard.set(token, forKey: Self.deviceTokenKey)
        registrationError = nil
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        registrationError = error.localizedDescription
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        publish(notification: notification)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        publish(notification: response.notification)
        completionHandler()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        publish(payload: PushNotificationPayload(userInfo: userInfo))
        completionHandler(.newData)
    }

    static func tokenString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func publish(notification: UNNotification) {
        publish(payload: PushNotificationPayload(userInfo: notification.request.content.userInfo))
    }

    private func publish(payload: PushNotificationPayload) {
        NotificationCenter.default.post(
            name: .finTrackPushReceived,
            object: nil,
            userInfo: ["payload": payload]
        )
    }
}
