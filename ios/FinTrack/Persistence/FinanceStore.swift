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
    @Published private(set) var isSyncingTransactions = false
    @Published var errorMessage: String?

    var pendingTransactionCount: Int {
        transactions.filter { apiID(from: $0.externalReference) == nil }.count
    }

    private let context: NSManagedObjectContext
    private let api = FinMateAPIClient()

    init(persistence: PersistenceController = .shared) {
        context = persistence.container.viewContext
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

    private func persist() throws {
        if context.hasChanges { try context.save() }
        try reload()
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
