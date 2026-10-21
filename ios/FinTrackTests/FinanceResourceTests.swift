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
