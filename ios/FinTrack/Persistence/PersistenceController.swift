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

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = NSManagedObjectModel()
        model.entities = [Self.transactionEntity(), Self.categoryEntity(), Self.budgetEntity()]
        container = NSPersistentContainer(name: "FinTrack", managedObjectModel: model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            container.persistentStoreDescriptions.first?.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        }
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
}
