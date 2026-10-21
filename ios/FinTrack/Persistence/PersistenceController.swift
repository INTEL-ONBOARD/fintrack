import CoreData

@objc(TransactionEntity)
final class TransactionEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var kind: String
    @NSManaged var amountMinor: Int64
    @NSManaged var currency: String
    @NSManaged var occurredAt: Date
    @NSManaged var categoryID: UUID?
    @NSManaged var merchant: String
    @NSManaged var note: String
    @NSManaged var tagsData: Data
    @NSManaged var paymentMethod: String
    @NSManaged var source: String
    @NSManaged var externalReference: String?
    @NSManaged var latitude: NSNumber?
    @NSManaged var longitude: NSNumber?
    @NSManaged var locationName: String?
}

@objc(CategoryEntity)
final class CategoryEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var kind: String
    @NSManaged var color: String
}

@objc(BudgetEntity)
final class BudgetEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var month: String
    @NSManaged var categoryID: UUID?
    @NSManaged var amountMinor: Int64
    @NSManaged var currency: String
}

@objc(AccountEntity)
final class AccountEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var serverID: String?
    @NSManaged var name: String
    @NSManaged var type: String
    @NSManaged var balanceMinor: Int64
    @NSManaged var limitMinor: Int64
    @NSManaged var color: String
    @NSManaged var bank: String
}

@objc(GoalEntity)
final class GoalEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var serverID: String?
    @NSManaged var name: String
    @NSManaged var icon: String
    @NSManaged var targetMinor: Int64
    @NSManaged var currentMinor: Int64
    @NSManaged var color: String
    @NSManaged var deadline: String
}

@objc(BillEntity)
final class BillEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var serverID: String?
    @NSManaged var name: String
    @NSManaged var amountMinor: Int64
    @NSManaged var dueDay: Int64
    @NSManaged var category: String
    @NSManaged var color: String
    @NSManaged var paid: Bool
}

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = NSManagedObjectModel()
        model.entities = [
            Self.transactionEntity(), Self.categoryEntity(), Self.budgetEntity(),
            Self.accountEntity(), Self.goalEntity(), Self.billEntity()
        ]
        container = NSPersistentContainer(name: "FinTrack", managedObjectModel: model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            container.persistentStoreDescriptions.first?.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        }
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { fatalError("Unable to load local finance data: \(loadError)") }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false, defaultValue: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }

    private static func entity(_ name: String, className: String, attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = className
        entity.properties = attributes
        entity.uniquenessConstraints = [["id"]]
        return entity
    }

    private static func transactionEntity() -> NSEntityDescription {
        entity("Transaction", className: NSStringFromClass(TransactionEntity.self), attributes: [
            attribute("id", .UUIDAttributeType),
            attribute("kind", .stringAttributeType),
            attribute("amountMinor", .integer64AttributeType),
            attribute("currency", .stringAttributeType),
            attribute("occurredAt", .dateAttributeType),
            attribute("categoryID", .UUIDAttributeType, optional: true),
            attribute("merchant", .stringAttributeType),
            attribute("note", .stringAttributeType),
            attribute("tagsData", .binaryDataAttributeType),
            attribute("paymentMethod", .stringAttributeType),
            attribute("source", .stringAttributeType),
            attribute("externalReference", .stringAttributeType, optional: true),
            attribute("latitude", .doubleAttributeType, optional: true),
            attribute("longitude", .doubleAttributeType, optional: true),
            attribute("locationName", .stringAttributeType, optional: true)
        ])
    }

    private static func categoryEntity() -> NSEntityDescription {
        entity("Category", className: NSStringFromClass(CategoryEntity.self), attributes: [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("kind", .stringAttributeType),
            attribute("color", .stringAttributeType)
        ])
    }

    private static func budgetEntity() -> NSEntityDescription {
        entity("Budget", className: NSStringFromClass(BudgetEntity.self), attributes: [
            attribute("id", .UUIDAttributeType),
            attribute("month", .stringAttributeType),
            attribute("categoryID", .UUIDAttributeType, optional: true),
            attribute("amountMinor", .integer64AttributeType),
            attribute("currency", .stringAttributeType)
        ])
    }

    private static func accountEntity() -> NSEntityDescription {
        entity("Account", className: NSStringFromClass(AccountEntity.self), attributes: [
            attribute("id", .UUIDAttributeType),
            attribute("serverID", .stringAttributeType, optional: true),
            attribute("name", .stringAttributeType),
            attribute("type", .stringAttributeType),
            attribute("balanceMinor", .integer64AttributeType),
            attribute("limitMinor", .integer64AttributeType),
            attribute("color", .stringAttributeType),
            attribute("bank", .stringAttributeType)
        ])
    }

    private static func goalEntity() -> NSEntityDescription {
        entity("Goal", className: NSStringFromClass(GoalEntity.self), attributes: [
            attribute("id", .UUIDAttributeType),
            attribute("serverID", .stringAttributeType, optional: true),
            attribute("name", .stringAttributeType),
            attribute("icon", .stringAttributeType),
            attribute("targetMinor", .integer64AttributeType),
            attribute("currentMinor", .integer64AttributeType),
            attribute("color", .stringAttributeType),
            attribute("deadline", .stringAttributeType)
        ])
    }

    private static func billEntity() -> NSEntityDescription {
        entity("Bill", className: NSStringFromClass(BillEntity.self), attributes: [
            attribute("id", .UUIDAttributeType),
            attribute("serverID", .stringAttributeType, optional: true),
            attribute("name", .stringAttributeType),
            attribute("amountMinor", .integer64AttributeType),
            attribute("dueDay", .integer64AttributeType),
            attribute("category", .stringAttributeType),
            attribute("color", .stringAttributeType),
            attribute("paid", .booleanAttributeType)
        ])
    }
}
