import CoreData
import Foundation

enum FinanceStoreError: LocalizedError {
    case invalidAmount
    case invalidCategory
    case duplicateCategory
    case duplicateBudget
    case duplicateImport
    case categoryInUse
    case missingLocalModel

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter an amount greater than zero."
        case .invalidCategory: "Enter a category name."
        case .duplicateCategory: "A category with this name already exists."
        case .duplicateBudget: "A budget already exists for this month and category."
        case .duplicateImport: "This imported transaction already exists."
        case .categoryInUse: "This category is used by a transaction or budget."
        case .missingLocalModel: "The local data model is unavailable."
        }
    }
}

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var transactions: [FinanceTransaction] = []
    @Published private(set) var categories: [FinanceCategory] = []
    @Published private(set) var budgets: [FinanceBudget] = []
    @Published private(set) var accounts: [FinanceAccount] = []
    @Published private(set) var goals: [FinanceGoal] = []
    @Published private(set) var bills: [FinanceBill] = []
    @Published private(set) var notifications: [FinanceNotification] = []
    @Published private(set) var settings: FinanceUserSettings
    @Published private(set) var isSyncingTransactions = false
    @Published private(set) var isSyncingResources = false
    @Published var errorMessage: String?

    var pendingTransactionCount: Int {
        transactions.filter { apiID(from: $0.externalReference) == nil }.count
    }

    var pendingResourceCount: Int {
        accounts.filter { $0.serverID == nil }.count
            + goals.filter { $0.serverID == nil }.count
            + bills.filter { $0.serverID == nil }.count
            + notifications.filter { $0.serverID == nil }.count
    }

    private let context: NSManagedObjectContext
    private let api = FinMateAPIClient()

    init(persistence: PersistenceController = .shared) {
        context = persistence.container.viewContext
        if let data = UserDefaults.standard.data(forKey: "financeUserSettings"),
           let saved = try? JSONDecoder().decode(FinanceUserSettings.self, from: data) {
            settings = saved
        } else {
            settings = FinanceUserSettings()
        }
        do {
            try seedCategoriesIfNeeded()
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() throws {
        let transactionRequest = NSFetchRequest<TransactionEntity>(entityName: "Transaction")
        transactionRequest.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]
        transactions = try context.fetch(transactionRequest).map(Self.transaction)

        let categoryRequest = NSFetchRequest<CategoryEntity>(entityName: "Category")
        categoryRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        categories = try context.fetch(categoryRequest).map(Self.category)

        let budgetRequest = NSFetchRequest<BudgetEntity>(entityName: "Budget")
        budgetRequest.sortDescriptors = [NSSortDescriptor(key: "month", ascending: false)]
        budgets = try context.fetch(budgetRequest).map(Self.budget)

        let accountRequest = NSFetchRequest<AccountEntity>(entityName: "Account")
        accountRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        accounts = try context.fetch(accountRequest).map(Self.account)

        let goalRequest = NSFetchRequest<GoalEntity>(entityName: "Goal")
        goalRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        goals = try context.fetch(goalRequest).map(Self.goal)

        let billRequest = NSFetchRequest<BillEntity>(entityName: "Bill")
        billRequest.sortDescriptors = [NSSortDescriptor(key: "dueDay", ascending: true)]
        bills = try context.fetch(billRequest).map(Self.bill)

        let notificationRequest = NSFetchRequest<NotificationEntity>(entityName: "Notification")
        notificationRequest.sortDescriptors = [NSSortDescriptor(key: "time", ascending: false)]
        notifications = try context.fetch(notificationRequest).map(Self.notification)
    }

    func deleteAllLocalData() throws {
        for entityName in ["Transaction", "Category", "Budget", "Account", "Goal", "Bill", "Notification"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
        try context.save()
        settings = FinanceUserSettings()
        UserDefaults.standard.removeObject(forKey: "financeUserSettings")
        try seedCategoriesIfNeeded()
        try reload()
    }

    func save(_ transaction: FinanceTransaction) throws {
        guard transaction.amountMinor > 0 else { throw FinanceStoreError.invalidAmount }
        if let reference = transaction.externalReference,
           transactions.contains(where: {
               $0.id != transaction.id && $0.source == transaction.source && sameReference($0.externalReference, reference)
           }) {
            throw FinanceStoreError.duplicateImport
        }
        let entity = try find(TransactionEntity.self, named: "Transaction", id: transaction.id)
            ?? insert(TransactionEntity.self, named: "Transaction")
        entity.id = transaction.id
        entity.kind = transaction.kind.rawValue
        entity.amountMinor = transaction.amountMinor
        entity.currency = transaction.currency
        entity.occurredAt = transaction.occurredAt
        entity.categoryID = transaction.categoryID
        entity.merchant = transaction.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        entity.note = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entity.tagsData = try JSONEncoder().encode(transaction.tags)
        entity.paymentMethod = transaction.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        entity.source = transaction.source.rawValue
        entity.externalReference = transaction.externalReference
        entity.latitude = transaction.latitude.map(NSNumber.init(value:))
        entity.longitude = transaction.longitude.map(NSNumber.init(value:))
        entity.locationName = transaction.locationName
        try persist()
    }

    func delete(_ transaction: FinanceTransaction) throws {
        if let entity = try find(TransactionEntity.self, named: "Transaction", id: transaction.id) {
            context.delete(entity)
            try persist()
        }
    }

    func deleteTransaction(_ transaction: FinanceTransaction, accessToken: String?) async {
        do {
            if let accessToken, let serverID = apiID(from: transaction.externalReference) {
                try await api.deleteTransaction(id: serverID, accessToken: accessToken)
            }
            try delete(transaction)
        } catch {
            errorMessage = "The transaction could not be deleted online: \(error.localizedDescription)"
        }
    }

    func pushTransaction(_ transaction: FinanceTransaction, accessToken: String) async {
        do {
            try await pushRemoteTransaction(transaction, accessToken: accessToken)
        } catch {
            errorMessage = "Saved on this device, but online save failed: \(error.localizedDescription)"
        }
    }

    func syncTransactions(accessToken: String) async {
        isSyncingTransactions = true
        defer { isSyncingTransactions = false }

        do {
            let remoteTransactions = try await api.listTransactions(accessToken: accessToken)
            for remoteTransaction in remoteTransactions {
                guard let localTransaction = localTransaction(from: remoteTransaction) else { continue }
                try save(localTransaction)
            }
            await uploadPendingTransactions(accessToken: accessToken)
        } catch {
            errorMessage = "Transaction sync failed: \(error.localizedDescription)"
        }
    }

    func retryPendingTransactions(accessToken: String) async {
        guard !isSyncingTransactions else { return }
        isSyncingTransactions = true
        defer { isSyncingTransactions = false }
        await uploadPendingTransactions(accessToken: accessToken)
    }

    func save(_ budget: FinanceBudget) throws {
        guard budget.amountMinor > 0 else { throw FinanceStoreError.invalidAmount }
        guard !budgets.contains(where: {
            $0.id != budget.id && $0.month == budget.month && $0.categoryID == budget.categoryID
        }) else { throw FinanceStoreError.duplicateBudget }
        let entity = try find(BudgetEntity.self, named: "Budget", id: budget.id)
            ?? insert(BudgetEntity.self, named: "Budget")
        entity.id = budget.id
        entity.month = budget.month
        entity.categoryID = budget.categoryID
        entity.amountMinor = budget.amountMinor
        entity.currency = budget.currency
        try persist()
    }

    func delete(_ budget: FinanceBudget) throws {
        if let entity = try find(BudgetEntity.self, named: "Budget", id: budget.id) {
            context.delete(entity)
            try persist()
        }
    }

    func save(_ category: FinanceCategory) throws {
        let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceStoreError.invalidCategory }
        guard !categories.contains(where: {
            $0.id != category.id && $0.kind == category.kind && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { throw FinanceStoreError.duplicateCategory }
        let entity = try find(CategoryEntity.self, named: "Category", id: category.id)
            ?? insert(CategoryEntity.self, named: "Category")
        entity.id = category.id
        entity.name = name
        entity.kind = category.kind.rawValue
        entity.color = category.color
        try persist()
    }

    func delete(_ category: FinanceCategory) throws {
        guard !transactions.contains(where: { $0.categoryID == category.id }),
              !budgets.contains(where: { $0.categoryID == category.id }) else {
            throw FinanceStoreError.categoryInUse
        }
        if let entity = try find(CategoryEntity.self, named: "Category", id: category.id) {
            context.delete(entity)
            try persist()
        }
    }

    func save(_ account: FinanceAccount) throws {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceStoreError.invalidCategory }
        let entity = try find(AccountEntity.self, named: "Account", id: account.id)
            ?? insert(AccountEntity.self, named: "Account")
        entity.id = account.id
        entity.serverID = account.serverID
        entity.name = name
        entity.type = account.type.rawValue
        entity.balanceMinor = account.balanceMinor
        entity.limitMinor = account.limitMinor
        entity.color = account.color
        entity.bank = account.bank
        try persist()
    }

    func delete(_ account: FinanceAccount) throws {
        if let entity = try find(AccountEntity.self, named: "Account", id: account.id) {
            context.delete(entity)
            try persist()
        }
    }

    func save(_ goal: FinanceGoal) throws {
        let name = goal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceStoreError.invalidCategory }
        guard goal.targetMinor > 0 else { throw FinanceStoreError.invalidAmount }
        let entity = try find(GoalEntity.self, named: "Goal", id: goal.id)
            ?? insert(GoalEntity.self, named: "Goal")
        entity.id = goal.id
        entity.serverID = goal.serverID
        entity.name = name
        entity.icon = goal.icon
        entity.targetMinor = goal.targetMinor
        entity.currentMinor = goal.currentMinor
        entity.color = goal.color
        entity.deadline = goal.deadline
        try persist()
    }

    func delete(_ goal: FinanceGoal) throws {
        if let entity = try find(GoalEntity.self, named: "Goal", id: goal.id) {
            context.delete(entity)
            try persist()
        }
    }

    func save(_ bill: FinanceBill) throws {
        let name = bill.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceStoreError.invalidCategory }
        guard bill.amountMinor > 0 else { throw FinanceStoreError.invalidAmount }
        let entity = try find(BillEntity.self, named: "Bill", id: bill.id)
            ?? insert(BillEntity.self, named: "Bill")
        entity.id = bill.id
        entity.serverID = bill.serverID
        entity.name = name
        entity.amountMinor = bill.amountMinor
        entity.dueDay = Int64(min(max(bill.dueDay, 1), 31))
        entity.category = bill.category
        entity.color = bill.color
        entity.paid = bill.paid
        try persist()
    }

    func delete(_ bill: FinanceBill) throws {
        if let entity = try find(BillEntity.self, named: "Bill", id: bill.id) {
            context.delete(entity)
            try persist()
        }
    }

    func save(_ notification: FinanceNotification) throws {
        let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw FinanceStoreError.invalidCategory }
        let entity = try find(NotificationEntity.self, named: "Notification", id: notification.id)
            ?? insert(NotificationEntity.self, named: "Notification")
        entity.id = notification.id
        entity.serverID = notification.serverID
        entity.title = title
        entity.body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)
        entity.time = notification.time
        entity.read = notification.read
        entity.type = notification.type.rawValue
        try persist()
    }

    func delete(_ notification: FinanceNotification) throws {
        if let entity = try find(NotificationEntity.self, named: "Notification", id: notification.id) {
            context.delete(entity)
            try persist()
        }
    }

    func syncResources(accessToken: String) async {
        isSyncingResources = true
        defer { isSyncingResources = false }
        do {
            let remoteAccounts = try await api.listAccounts(accessToken: accessToken)
            let remoteGoals = try await api.listGoals(accessToken: accessToken)
            let remoteBills = try await api.listBills(accessToken: accessToken)
            let remoteNotifications = try await api.listNotifications(accessToken: accessToken)
            for item in remoteAccounts { if let local = localAccount(from: item) { try save(local) } }
            for item in remoteGoals { if let local = localGoal(from: item) { try save(local) } }
            for item in remoteBills { if let local = localBill(from: item) { try save(local) } }
            for item in remoteNotifications { if let local = localNotification(from: item) { try save(local) } }
            await uploadPendingResources(accessToken: accessToken)
        } catch {
            errorMessage = "Account, goal and bill sync failed: \(error.localizedDescription)"
        }
    }

    func syncSettings(accessToken: String) async {
        do {
            guard let remote = try await api.getSettings(accessToken: accessToken) else { return }
            var updated = settings
            updated.name = remote.name ?? updated.name
            updated.email = remote.email ?? updated.email
            updated.currency = remote.currency ?? updated.currency
            updated.notifications = remote.notifs ?? updated.notifications
            setSettings(updated)
        } catch {
            errorMessage = "Settings sync failed: \(error.localizedDescription)"
        }
    }

    func analyzeStatement(fileData: Data, fileName: String, accessToken: String) async throws -> StatementAnalysis {
        try await api.analyzeStatement(fileData: fileData, fileName: fileName, accessToken: accessToken)
    }

    func commitStatement(
        fileData: Data, fileName: String, accountName: String,
        mapping: StatementMapping, categoryOverrides: [Int: String] = [:],
        fingerprint: String?, bankLabel: String?, accessToken: String
    ) async throws -> StatementImportResult {
        let result = try await api.commitStatement(
            fileData: fileData, fileName: fileName, accountName: accountName,
            mapping: mapping, categoryOverrides: categoryOverrides,
            fingerprint: fingerprint, bankLabel: bankLabel, accessToken: accessToken
        )
        await syncTransactions(accessToken: accessToken)
        return result
    }

    func saveSettings(_ value: FinanceUserSettings, accessToken: String?) async {
        setSettings(value)
        guard let accessToken else { return }
        do {
            try await api.saveSettings(value, accessToken: accessToken)
        } catch {
            errorMessage = "Settings were saved on this device, but online save failed: \(error.localizedDescription)"
        }
    }

    func pushAccount(_ account: FinanceAccount, accessToken: String) async {
        do {
            if let serverID = account.serverID {
                try await api.updateAccount(id: serverID, account, accessToken: accessToken)
            } else {
                let remote = try await api.createAccount(account, accessToken: accessToken)
                try attachServerID(remote.id, to: account.id, entityName: "Account", type: AccountEntity.self)
            }
        } catch { errorMessage = "Saved on this device, but the account online save failed: \(error.localizedDescription)" }
    }

    func pushGoal(_ goal: FinanceGoal, accessToken: String) async {
        do {
            if let serverID = goal.serverID {
                try await api.updateGoal(id: serverID, goal, accessToken: accessToken)
            } else {
                let remote = try await api.createGoal(goal, accessToken: accessToken)
                try attachServerID(remote.id, to: goal.id, entityName: "Goal", type: GoalEntity.self)
            }
        } catch { errorMessage = "Saved on this device, but the goal online save failed: \(error.localizedDescription)" }
    }

    func pushBill(_ bill: FinanceBill, accessToken: String) async {
        do {
            if let serverID = bill.serverID {
                try await api.updateBill(id: serverID, bill, accessToken: accessToken)
            } else {
                let remote = try await api.createBill(bill, accessToken: accessToken)
                try attachServerID(remote.id, to: bill.id, entityName: "Bill", type: BillEntity.self)
            }
        } catch { errorMessage = "Saved on this device, but the bill online save failed: \(error.localizedDescription)" }
    }

    func deleteAccount(_ account: FinanceAccount, accessToken: String?) async {
        do { if let token = accessToken, let id = account.serverID { try await api.deleteAccount(id: id, accessToken: token) }; try delete(account) }
        catch { errorMessage = "The account could not be deleted: \(error.localizedDescription)" }
    }

    func deleteGoal(_ goal: FinanceGoal, accessToken: String?) async {
        do { if let token = accessToken, let id = goal.serverID { try await api.deleteGoal(id: id, accessToken: token) }; try delete(goal) }
        catch { errorMessage = "The goal could not be deleted: \(error.localizedDescription)" }
    }

    func deleteBill(_ bill: FinanceBill, accessToken: String?) async {
        do { if let token = accessToken, let id = bill.serverID { try await api.deleteBill(id: id, accessToken: token) }; try delete(bill) }
        catch { errorMessage = "The bill could not be deleted: \(error.localizedDescription)" }
    }

    func toggleBill(_ bill: FinanceBill, accessToken: String?) async {
        do {
            if let token = accessToken, let id = bill.serverID { try await api.toggleBillPaid(id: id, accessToken: token) }
            var changed = bill
            changed.paid.toggle()
            try save(changed)
        } catch { errorMessage = "The bill status could not be updated: \(error.localizedDescription)" }
    }

    func markNotificationRead(_ notification: FinanceNotification, accessToken: String?) async {
        do {
            if let token = accessToken, let id = notification.serverID { try await api.markNotificationRead(id: id, accessToken: token) }
            var changed = notification
            changed.read = true
            try save(changed)
        } catch { errorMessage = "The notification could not be marked read: \(error.localizedDescription)" }
    }

    func markAllNotificationsRead(accessToken: String?) async {
        do {
            if let token = accessToken { try await api.markAllNotificationsRead(accessToken: token) }
            for notification in notifications where !notification.read {
                var changed = notification
                changed.read = true
                try save(changed)
            }
        } catch { errorMessage = "The notifications could not be marked read: \(error.localizedDescription)" }
    }

    func pushNotification(_ notification: FinanceNotification, accessToken: String) async {
        do {
            if let serverID = notification.serverID {
                try await api.updateNotification(id: serverID, notification, accessToken: accessToken)
            } else {
                let remote = try await api.createNotification(notification, accessToken: accessToken)
                try attachServerID(remote.id, to: notification.id, entityName: "Notification", type: NotificationEntity.self)
            }
        } catch { errorMessage = "Saved on this device, but the notification online save failed: \(error.localizedDescription)" }
    }

    func deleteNotification(_ notification: FinanceNotification, accessToken: String?) async {
        do {
            if let token = accessToken, let id = notification.serverID { try await api.deleteNotification(id: id, accessToken: token) }
            try delete(notification)
        } catch { errorMessage = "The notification could not be deleted: \(error.localizedDescription)" }
    }

    private func persist() throws {
        if context.hasChanges { try context.save() }
        try reload()
    }

    private func setSettings(_ value: FinanceUserSettings) {
        settings = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "financeUserSettings")
        }
    }

    private func find<T: NSManagedObject>(_ type: T.Type, named name: String, id: UUID) throws -> T? {
        let request = NSFetchRequest<T>(entityName: name)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func insert<T: NSManagedObject>(_ type: T.Type, named name: String) throws -> T {
        guard let description = NSEntityDescription.entity(forEntityName: name, in: context) else {
            throw FinanceStoreError.missingLocalModel
        }
        return T(entity: description, insertInto: context)
    }

    private func seedCategoriesIfNeeded() throws {
        let request = NSFetchRequest<CategoryEntity>(entityName: "Category")
        guard try context.count(for: request) == 0 else { return }
        let defaults: [(String, TransactionKind, String)] = [
            ("Food & Dining", .expense, "#9B7BE8"),
            ("Groceries", .expense, "#6F9D80"),
            ("Transport", .expense, "#6D94C7"),
            ("Shopping", .expense, "#DB85AB"),
            ("Bills", .expense, "#D2A05C"),
            ("Health Care", .expense, "#68AFA4"),
            ("Education", .expense, "#7480C6"),
            ("Travel", .expense, "#9A79B8"),
            ("Subscriptions", .expense, "#7B91AA"),
            ("Other", .expense, "#A1A5B2"),
            ("Salary", .income, "#59A779"),
            ("Other Income", .income, "#6AB897")
        ]
        for item in defaults {
            let entity = try insert(CategoryEntity.self, named: "Category")
            entity.id = UUID()
            entity.name = item.0
            entity.kind = item.1.rawValue
            entity.color = item.2
        }
        try context.save()
    }

    private static func transaction(_ entity: TransactionEntity) -> FinanceTransaction {
        FinanceTransaction(
            id: entity.id, kind: TransactionKind(rawValue: entity.kind) ?? .other,
            amountMinor: entity.amountMinor, currency: entity.currency,
            occurredAt: entity.occurredAt, categoryID: entity.categoryID,
            merchant: entity.merchant, note: entity.note,
            tags: (try? JSONDecoder().decode([String].self, from: entity.tagsData)) ?? [],
            paymentMethod: entity.paymentMethod,
            source: TransactionSource(rawValue: entity.source) ?? .manual,
            externalReference: entity.externalReference,
            latitude: entity.latitude?.doubleValue,
            longitude: entity.longitude?.doubleValue,
            locationName: entity.locationName
        )
    }

    private static func category(_ entity: CategoryEntity) -> FinanceCategory {
        FinanceCategory(
            id: entity.id, name: entity.name,
            kind: TransactionKind(rawValue: entity.kind) ?? .expense, color: entity.color
        )
    }

    private static func budget(_ entity: BudgetEntity) -> FinanceBudget {
        FinanceBudget(
            id: entity.id, month: entity.month,
            categoryID: entity.categoryID, amountMinor: entity.amountMinor,
            currency: entity.currency
        )
    }

    private static func account(_ entity: AccountEntity) -> FinanceAccount {
        FinanceAccount(
            id: entity.id, serverID: entity.serverID, name: entity.name,
            type: FinanceAccountType(rawValue: entity.type) ?? .checking,
            balanceMinor: entity.balanceMinor, limitMinor: entity.limitMinor,
            color: entity.color, bank: entity.bank
        )
    }

    private static func goal(_ entity: GoalEntity) -> FinanceGoal {
        FinanceGoal(
            id: entity.id, serverID: entity.serverID, name: entity.name,
            icon: entity.icon, targetMinor: entity.targetMinor,
            currentMinor: entity.currentMinor, color: entity.color,
            deadline: entity.deadline
        )
    }

    private static func bill(_ entity: BillEntity) -> FinanceBill {
        FinanceBill(
            id: entity.id, serverID: entity.serverID, name: entity.name,
            amountMinor: entity.amountMinor, dueDay: Int(entity.dueDay),
            category: entity.category, color: entity.color, paid: entity.paid
        )
    }

    private static func notification(_ entity: NotificationEntity) -> FinanceNotification {
        FinanceNotification(
            id: entity.id, serverID: entity.serverID, title: entity.title,
            body: entity.body, time: entity.time, read: entity.read,
            type: FinanceNotificationType(rawValue: entity.type) ?? .info
        )
    }

    private func localAccount(from remote: RemoteAccount) -> FinanceAccount? {
        let existing = accounts.first { $0.serverID == remote.id }
        return FinanceAccount(
            id: existing?.id ?? UUID(), serverID: remote.id,
            name: remote.name ?? existing?.name ?? "Account",
            type: FinanceAccountType(rawValue: remote.type ?? "") ?? existing?.type ?? .checking,
            balanceMinor: remote.balance.map { Int64(($0 * 100).rounded()) } ?? existing?.balanceMinor ?? 0,
            limitMinor: remote.limit.map { Int64(($0 * 100).rounded()) } ?? existing?.limitMinor ?? 0,
            color: remote.color ?? existing?.color ?? "#2E9D68",
            bank: remote.bank ?? existing?.bank ?? ""
        )
    }

    private func localGoal(from remote: RemoteGoal) -> FinanceGoal? {
        let existing = goals.first { $0.serverID == remote.id }
        return FinanceGoal(
            id: existing?.id ?? UUID(), serverID: remote.id,
            name: remote.name ?? existing?.name ?? "Goal",
            icon: remote.icon ?? existing?.icon ?? "target",
            targetMinor: remote.target.map { Int64(($0 * 100).rounded()) } ?? existing?.targetMinor ?? 0,
            currentMinor: remote.current.map { Int64(($0 * 100).rounded()) } ?? existing?.currentMinor ?? 0,
            color: remote.color ?? existing?.color ?? "#2E9D68",
            deadline: remote.deadline ?? existing?.deadline ?? ""
        )
    }

    private func localBill(from remote: RemoteBill) -> FinanceBill? {
        let existing = bills.first { $0.serverID == remote.id }
        return FinanceBill(
            id: existing?.id ?? UUID(), serverID: remote.id,
            name: remote.name ?? existing?.name ?? "Bill",
            amountMinor: remote.amount.map { Int64((abs($0) * 100).rounded()) } ?? existing?.amountMinor ?? 0,
            dueDay: remote.dueDay ?? existing?.dueDay ?? 1,
            category: remote.category ?? existing?.category ?? "Bills",
            color: remote.color ?? existing?.color ?? "#4886D2",
            paid: remote.paid ?? existing?.paid ?? false
        )
    }

    private func localNotification(from remote: RemoteNotification) -> FinanceNotification? {
        let existing = notifications.first { $0.serverID == remote.id }
        return FinanceNotification(
            id: existing?.id ?? UUID(), serverID: remote.id,
            title: remote.title ?? existing?.title ?? "Notification",
            body: remote.body ?? existing?.body ?? "",
            time: remote.time ?? existing?.time ?? "",
            read: remote.read ?? existing?.read ?? false,
            type: FinanceNotificationType(rawValue: remote.type ?? "") ?? existing?.type ?? .info
        )
    }

    private func attachServerID(_ serverID: String, to localID: UUID, entityName: String, type: AccountEntity.Type) throws {
        guard let entity = try find(type, named: entityName, id: localID) else { return }
        entity.serverID = serverID
        try persist()
    }

    private func attachServerID(_ serverID: String, to localID: UUID, entityName: String, type: GoalEntity.Type) throws {
        guard let entity = try find(type, named: entityName, id: localID) else { return }
        entity.serverID = serverID
        try persist()
    }

    private func attachServerID(_ serverID: String, to localID: UUID, entityName: String, type: BillEntity.Type) throws {
        guard let entity = try find(type, named: entityName, id: localID) else { return }
        entity.serverID = serverID
        try persist()
    }

    private func attachServerID(_ serverID: String, to localID: UUID, entityName: String, type: NotificationEntity.Type) throws {
        guard let entity = try find(type, named: entityName, id: localID) else { return }
        entity.serverID = serverID
        try persist()
    }

    private func uploadPendingResources(accessToken: String) async {
        for account in accounts where account.serverID == nil { await pushAccount(account, accessToken: accessToken) }
        for goal in goals where goal.serverID == nil { await pushGoal(goal, accessToken: accessToken) }
        for bill in bills where bill.serverID == nil { await pushBill(bill, accessToken: accessToken) }
        for notification in notifications where notification.serverID == nil { await pushNotification(notification, accessToken: accessToken) }
    }

    private func localTransaction(from remote: RemoteTransaction) -> FinanceTransaction? {
        guard let remoteAmount = remote.amount, remoteAmount != 0 else { return nil }

        let kind: TransactionKind = remoteAmount < 0 ? .expense : .income
        let amountMinor = Int64((abs(remoteAmount) * 100).rounded())
        guard amountMinor > 0 else { return nil }

        let existingTransaction = transactions.first(where: {
            apiID(from: $0.externalReference) == remote.id
        })
        let externalReference = existingTransaction?.externalReference ?? "api:\(remote.id)"
        let localID = existingTransaction?.id ?? UUID()

        var occurredAt = Date.now
        if let dateText = remote.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let parsedDate = formatter.date(from: dateText) {
                occurredAt = parsedDate
            }
        }

        let remoteCategoryID: UUID?
        if let categoryName = remote.category {
            remoteCategoryID = categoryID(named: categoryName, kind: kind)
        } else {
            remoteCategoryID = nil
        }
        return FinanceTransaction(
            id: localID,
            kind: kind,
            amountMinor: amountMinor,
            currency: remote.currency ?? "LKR",
            occurredAt: occurredAt,
            categoryID: remoteCategoryID,
            merchant: remote.name ?? "",
            note: remote.note ?? "",
            paymentMethod: remote.account ?? "",
            source: .manual,
            externalReference: externalReference
        )
    }

    private func categoryID(named name: String, kind: TransactionKind) -> UUID? {
        categories.first {
            $0.kind == kind && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }?.id
    }

    private func categoryName(for transaction: FinanceTransaction) -> String? {
        transaction.categoryID.flatMap { categoryID in
            categories.first(where: { $0.id == categoryID })?.name
        }
    }

    private func uploadPendingTransactions(accessToken: String) async {
        let pending = transactions.filter { apiID(from: $0.externalReference) == nil }
        for transaction in pending {
            do {
                try await pushRemoteTransaction(transaction, accessToken: accessToken)
            } catch {
                errorMessage = "Saved on this device, but online save failed: \(error.localizedDescription)"
                return
            }
        }
    }

    private func pushRemoteTransaction(_ transaction: FinanceTransaction, accessToken: String) async throws {
        let category = categoryName(for: transaction)
        if let serverID = apiID(from: transaction.externalReference) {
            try await api.updateTransaction(
                id: serverID,
                transaction,
                categoryName: category,
                accessToken: accessToken
            )
        } else {
            let remote = try await api.createTransaction(
                transaction,
                categoryName: category,
                accessToken: accessToken
            )
            try attachRemoteID(remote.id, to: transaction.id, originalReference: transaction.externalReference)
        }
    }

    private func attachRemoteID(_ serverID: String, to localID: UUID, originalReference: String?) throws {
        guard let entity = try find(TransactionEntity.self, named: "Transaction", id: localID) else { return }
        if let originalReference, !originalReference.hasPrefix("api:") {
            entity.externalReference = "api:\(serverID)|\(originalReference)"
        } else {
            entity.externalReference = "api:\(serverID)"
        }
        try persist()
    }

    private func apiID(from reference: String?) -> String? {
        guard let reference, reference.hasPrefix("api:") else { return nil }
        let value = reference.dropFirst(4)
        return value.split(separator: "|", maxSplits: 1).first.map(String.init)
    }

    private func sameReference(_ storedReference: String?, _ reference: String) -> Bool {
        guard let storedReference else { return false }
        return storedReference == reference || storedReference.hasSuffix("|\(reference)")
    }
}
