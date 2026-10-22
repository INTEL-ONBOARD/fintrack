import Foundation
import Testing
@testable import FinTrack

@Test @MainActor func accountGoalAndBillCanBeStoredLocally() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let account = FinanceAccount(name: "Daily account", balanceMinor: 125_050, bank: "Example Bank")
    let goal = FinanceGoal(name: "Emergency fund", targetMinor: 500_000, currentMinor: 125_000)
    let bill = FinanceBill(name: "Internet", amountMinor: 7_500, dueDay: 12)

    try store.save(account)
    try store.save(goal)
    try store.save(bill)

    #expect(store.accounts.first(where: { $0.id == account.id })?.balanceMinor == 125_050)
    #expect(store.goals.first(where: { $0.id == goal.id })?.currentMinor == 125_000)
    #expect(store.bills.first(where: { $0.id == bill.id })?.dueDay == 12)
}

@Test @MainActor func resourcesRejectMissingNamesAndInvalidAmounts() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))

    do {
        try store.save(FinanceGoal(name: "", targetMinor: 10_000))
        Issue.record("A goal without a name should fail")
    } catch FinanceStoreError.invalidCategory {
    }

    do {
        try store.save(FinanceBill(name: "Invalid bill", amountMinor: 0))
        Issue.record("A bill with no amount should fail")
    } catch FinanceStoreError.invalidAmount {
    }

    do {
        try store.save(FinanceGoal(name: "Invalid goal", targetMinor: 0))
        Issue.record("A goal with no target should fail")
    } catch FinanceStoreError.invalidAmount {
    }
}

@Test @MainActor func billDueDayIsKeptInsideCalendarRange() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let bill = FinanceBill(name: "Annual fee", amountMinor: 2_000, dueDay: 45)

    try store.save(bill)

    #expect(store.bills.first?.dueDay == 31)
}

@Test func resourceRequestsConvertMinorUnitsToApiAmounts() throws {
    let accountData = try JSONEncoder().encode(
        RemoteAccountRequest(account: FinanceAccount(name: "Savings", balanceMinor: 125_050, limitMinor: 500_000))
    )
    let goalData = try JSONEncoder().encode(
        RemoteGoalRequest(goal: FinanceGoal(name: "Trip", targetMinor: 250_000, currentMinor: 75_000))
    )
    let billData = try JSONEncoder().encode(
        RemoteBillRequest(bill: FinanceBill(name: "Phone", amountMinor: 3_250, dueDay: 8))
    )

    let account = try #require(try JSONSerialization.jsonObject(with: accountData) as? [String: Any])
    let goal = try #require(try JSONSerialization.jsonObject(with: goalData) as? [String: Any])
    let bill = try #require(try JSONSerialization.jsonObject(with: billData) as? [String: Any])
    #expect(account["balance"] as? Double == 1_250.50)
    #expect(goal["target"] as? Double == 2_500.00)
    #expect(bill["amount"] as? Double == 32.50)
}

@Test @MainActor func notificationCanBeStoredAndMarkedReadLocally() async throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let notification = FinanceNotification(title: "Bill reminder", body: "Internet is due soon")

    try store.save(notification)
    #expect(store.notifications.first?.read == false)

    await store.markNotificationRead(notification, accessToken: nil)
    #expect(store.notifications.first?.read == true)
}

@Test func notificationRequestKeepsServerFieldNames() throws {
    let data = try JSONEncoder().encode(RemoteNotificationRequest(notification: FinanceNotification(
        title: "Bill reminder", body: "Internet is due soon", time: "2026-10-21T12:00:00.000Z", type: .alert
    )))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["title"] as? String == "Bill reminder")
    #expect(json["body"] as? String == "Internet is due soon")
    #expect(json["type"] as? String == "alert")
    #expect(json["read"] as? Bool == false)
}

@Test func pushPayloadDecodesAlertAndDataFields() {
    let payload = PushNotificationPayload(userInfo: [
        "aps": ["alert": ["title": "Budget warning", "body": "Budget is almost full."]],
        "data": ["id": "push-1", "type": "alert", "time": "2026-10-22T10:00:00Z"]
    ])

    #expect(payload.id == "push-1")
    #expect(payload.title == "Budget warning")
    #expect(payload.body == "Budget is almost full.")
    #expect(payload.type == .alert)
    #expect(PushNotificationService.tokenString(from: Data([0x01, 0xab])) == "01ab")
}

@Test @MainActor func pushNotificationIsSavedOnceLocally() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let payload = PushNotificationPayload(userInfo: [
        "id": "push-1",
        "title": "Bill reminder",
        "body": "Internet is due soon"
    ])

    try store.savePushNotification(payload)
    try store.savePushNotification(payload)

    #expect(store.notifications.count == 1)
    #expect(store.notifications.first?.serverID == "push-1")
}

@Test func settingsRequestKeepsCurrencyAndNotificationPreferences() throws {
    let settings = FinanceUserSettings(
        name: "Alex", email: "alex@example.com", currency: "LKR",
        notifications: ["billAlerts": true, "monthlySummary": false]
    )
    let data = try JSONEncoder().encode(RemoteSettingsRequest(settings: settings))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let notifs = try #require(json["notifs"] as? [String: Bool])

    #expect(json["name"] as? String == "Alex")
    #expect(json["currency"] as? String == "LKR")
    #expect(notifs["billAlerts"] == true)
    #expect(notifs["monthlySummary"] == false)
}

@Test func sessionResponseDecodesDeviceAndActivityFields() throws {
    let data = Data("""
    [{"sessionId":"session-1","userId":"u_123","deviceLabel":"iPhone","createdAt":"2026-10-21T10:00:00.000Z","lastActiveAt":"2026-10-21T12:00:00.000Z"}]
    """.utf8)
    let sessions = try JSONDecoder().decode([RemoteSession].self, from: data)

    #expect(sessions.count == 1)
    #expect(sessions.first?.id == "session-1")
    #expect(sessions.first?.deviceLabel == "iPhone")
}

@Test func statementMappingUsesApiFieldNames() throws {
    let mapping = StatementMapping(
        model: "signed", date: 0, description: 1, balance: 2,
        amount: nil, debit: nil, credit: nil, drcr: nil,
        dateFormat: "yyyy-MM-dd",
        numberStyle: StatementNumberStyle(decimal: ".", thousands: ","),
        currency: "LKR"
    )
    let data = try JSONEncoder().encode(mapping)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["date_format"] as? String == "yyyy-MM-dd")
    #expect(json["number_style"] as? [String: String] == ["decimal": ".", "thousands": ","])
    #expect(json["description"] as? Int == 1)
}

@Test func multipartStatementBodyContainsFileAndCommitFields() throws {
    let body = FinMateAPIClient.multipartBody(
        fileData: Data("date,name\n2026-10-21,Shop".utf8),
        fileName: "statement.csv",
        fields: ["accountName": "Checking", "mapping": "{\"model\":\"signed\"}"],
        boundary: "test-boundary"
    )
    let text = try #require(String(data: body, encoding: .utf8))

    #expect(text.contains("name=\"file\"; filename=\"statement.csv\""))
    #expect(text.contains("name=\"accountName\""))
    #expect(text.contains("Checking"))
    #expect(text.contains("date,name"))
}

@Test func accountSecurityRequestsUseExpectedApiKeys() throws {
    let changeData = try JSONEncoder().encode(ChangePasswordRequest(oldPassword: "old-pass", newPassword: "new-pass-123"))
    let resetData = try JSONEncoder().encode(ResetPasswordRequest(token: "reset-token", newPassword: "new-pass-123"))
    let emailData = try JSONEncoder().encode(EmailRequest(email: "alex@example.com"))

    let change = try #require(try JSONSerialization.jsonObject(with: changeData) as? [String: String])
    let reset = try #require(try JSONSerialization.jsonObject(with: resetData) as? [String: String])
    let email = try #require(try JSONSerialization.jsonObject(with: emailData) as? [String: String])
    #expect(change["oldPassword"] == "old-pass")
    #expect(change["newPassword"] == "new-pass-123")
    #expect(reset["token"] == "reset-token")
    #expect(email["email"] == "alex@example.com")
}

@Test func authResponseDecodesVerificationSession() throws {
    let data = Data("""
    {"user":{"id":"u_1","name":"Alex","email":"alex@example.com","avatar":null},"sessionId":"session-1","accessToken":"access","refreshToken":"refresh"}
    """.utf8)
    let response = try JSONDecoder().decode(AuthResponse.self, from: data)
    #expect(response.sessionId == "session-1")
    #expect(response.user.email == "alex@example.com")
}

@Test func profileExtraRequestsUseExpectedFields() throws {
    let avatarData = try JSONEncoder().encode(AvatarRequest(avatar: "data:image/png;base64,abc"))
    let emailData = try JSONEncoder().encode(MonthlyEmailRequest(optIn: false))
    let avatar = try #require(try JSONSerialization.jsonObject(with: avatarData) as? [String: String])
    let email = try #require(try JSONSerialization.jsonObject(with: emailData) as? [String: Bool])

    #expect(avatar["avatar"] == "data:image/png;base64,abc")
    #expect(email["optIn"] == false)
}

@Test func avatarResponseDecodesSavedDataUri() throws {
    let data = Data("{\"ok\":true,\"avatar\":\"data:image/png;base64,abc\"}".utf8)
    let response = try JSONDecoder().decode(AvatarResponse.self, from: data)
    #expect(response.ok)
    #expect(response.avatar.hasPrefix("data:image/png"))
}

@Test @MainActor func localDataResetRemovesFinanceRecordsAndRestoresCategories() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    try store.save(FinanceTransaction(kind: .expense, amountMinor: 1_500))
    try store.save(FinanceAccount(name: "Checking", balanceMinor: 50_000))
    try store.save(FinanceGoal(name: "Trip", targetMinor: 100_000))
    try store.save(FinanceBill(name: "Internet", amountMinor: 6_000))
    try store.save(FinanceNotification(title: "Reminder", body: "Pay bill"))

    try store.deleteAllLocalData()

    #expect(store.transactions.isEmpty)
    #expect(store.accounts.isEmpty)
    #expect(store.goals.isEmpty)
    #expect(store.bills.isEmpty)
    #expect(store.notifications.isEmpty)
    #expect(!store.categories.isEmpty)
}

@Test func chatMessageRequestUsesConversationAndBody() throws {
    let data = try JSONEncoder().encode(SendMessageRequest(conversationId: "group", body: "Hello"))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(json["conversationId"] == "group")
    #expect(json["body"] == "Hello")
}

@Test func chatMessageResponseDecodesServerId() throws {
    let data = Data("{\"ok\":true,\"id\":\"message-1\"}".utf8)
    let response = try JSONDecoder().decode(SendMessageResponse.self, from: data)
    #expect(response.ok)
    #expect(response.id == "message-1")
}

@Test func realtimeSocketEventNamesRouteToResourceRefreshes() {
    #expect(RealtimeSyncEvent(serverEventName: "transactions:created") == .transactions)
    #expect(RealtimeSyncEvent(serverEventName: "notifications:read-all") == .notifications)
    #expect(RealtimeSyncEvent(serverEventName: "settings:updated") == .settings)
    #expect(RealtimeSyncEvent(serverEventName: "presence:update") == .unknown)
}

@Test func realtimeSocketEventPacketDecodesEventName() {
    #expect(RealtimeSyncService.eventName(from: "42[\"bills:updated\",{\"id\":\"1\"}]") == "bills:updated")
    #expect(RealtimeSyncService.eventName(from: "2") == nil)
}

@Test func deviceTokenRequestUsesIosPlatform() throws {
    let data = try JSONEncoder().encode(
        DeviceTokenRegistrationRequest(token: "abc123", platform: "ios")
    )
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(json["token"] == "abc123")
    #expect(json["platform"] == "ios")
}
