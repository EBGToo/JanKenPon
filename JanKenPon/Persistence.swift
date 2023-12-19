//
//  Persistence.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import CoreData
import CloudKit

extension CKDatabase.Scope {
    public var name: String {
        switch self {
        case .public:  return "public"
        case .private: return "private"
        case .shared:  return "shared"
        @unknown default:
            return "default"
        }
    }
}

class PersistenceController: NSObject, ObservableObject {
    static let cloudKitContainerIdentifier = "iCloud.com.agdogfights.JanKenPon"
    static let cloudKitContainerName        = "JanKenPon"

    static let bundleIdentifier = "com.agdogfights.JanKenPon"
    static let modelName = "JanKenPon"

    static let storeDidChangeName = Notification.Name("jankenponStoreDidChange")

    enum Configuration: String, CustomStringConvertible {
        case `default` = "Default"

        var description: String {
            return self.rawValue
        }
    }

    static let transactionAuthor = "What the Heck is This?"  // Another App is updating the transaction history?

    /// A lazy, singleton, shared PersistentController
    public static var shared: PersistenceController = {
        PersistenceController(inMemory: false)
    }()

    /// A lazy, singleton, shared, inMemory PersistenceController
    public static var preview: PersistenceController = {
        //
        // Populate w/ Defaults

        //        let result = PersistenceController(inMemory: true)
        //        let viewContext = result.container.viewContext
        //        for _ in 0..<10 {
        //            let newItem = Item(context: viewContext)
        //            newItem.timestamp = Date()
        //        }
        //        do {
        //            try viewContext.save()
        //        } catch {
        //            // Replace this implementation with code to handle the error appropriately.
        //            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        //            let nsError = error as NSError
        //            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        //        }
        //        return result

        return PersistenceController (inMemory: true)
    }()


    // The location for our CoreData database files
    private let baseURL: URL

    //
    // Common data for the 'storeDescription'
    //
    class StoreBundle {
        let scope: CKDatabase.Scope
        let url: URL
        let storeDesciption: NSPersistentStoreDescription
        var store: NSPersistentStore! = nil

        init (scope: CKDatabase.Scope, baseURL: URL, storeDesciption: NSPersistentStoreDescription) {
            self.scope = scope

            // All data will go in a 'scope'-specific filter
            let folderURL = baseURL.appendingPathComponent(scope.name)
            let fileManager = FileManager.default
            if !fileManager.fileExists (atPath: folderURL.path) {
                do {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                }
                catch {
                    fatalError("#\(#function): Failed to create the store folder: \(error)")
                }
            }
            self.url = folderURL.appendingPathComponent("database.sqlite")

            // Configure the description
            storeDesciption.url = self.url
            storeDesciption.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDesciption.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions (
                containerIdentifier: PersistenceController.cloudKitContainerIdentifier)
            cloudKitContainerOptions.databaseScope = self.scope

            storeDesciption.cloudKitContainerOptions = cloudKitContainerOptions
            self.storeDesciption = storeDesciption
        }
    }

    private var storeMap:Dictionary<CKDatabase.Scope,StoreBundle> = [:]

    public func storeFor (scope: CKDatabase.Scope) -> NSPersistentStore {
        guard let bundle = self.storeMap[scope]
        else { fatalError ("#\(#function): Failed storeFor(scope: \(scope.name))") }

        return bundle.store
    }

    public func storeFor (uuid: String) -> NSPersistentStore? {
        return storeMap.values.map(\.store).first { $0.identifier == uuid }
    }

    public func scopeFor (store: NSPersistentStore) -> CKDatabase.Scope? {
        return storeMap.values.first { $0.store == store }.map { $0.scope }
    }

    public func scopeFor (uuid: /* NSPersistentStore UUID */ String) -> CKDatabase.Scope? {
        return storeMap.values.first { $0.store.identifier == uuid }.map { $0.scope }
    }

    //
    // The Containers for this Controller
    //
    let container: NSPersistentCloudKitContainer

    var context: NSManagedObjectContext {
        container.viewContext
    }

    init (inMemory: Bool = false) {
        ValueTransformer.setValueTransformer(
            PersonNameComponentsValueTransformer(),
            forName: PersonNameComponentsValueTransformer.name)

        // Build a baseURL for storing the CoreData sqlite files
        self.baseURL = (inMemory
                        ? FileManager.default.temporaryDirectory //  URL (fileURLWithPath: "/dev/null")
                        : NSPersistentContainer.defaultDirectoryURL())
        .appendingPathComponent("CoreDataStores")

        // If 'inMemory', clear out baseURL
        if inMemory {
            try? FileManager.default.removeItem (at: self.baseURL)
        }

        // Construct a container for the `"ABScoring"` app's managed object model
        self.container = NSPersistentCloudKitContainer (name: PersistenceController.cloudKitContainerName) // ,managedObjectModel: Defaults.ManagedObject.mom)

        // Complete initialization
        super.init()

        //
        // Setup the {public, private, shared} StoreBundles
        //

        // Private storeDescription
        guard let storeDescriptionPrivate = container.persistentStoreDescriptions.first else {
            fatalError("#\(#function): Failed to retrieve a persistent store description.")
        }
        self.storeMap[CKDatabase.Scope.private] = StoreBundle(
            scope: CKDatabase.Scope.private,
            baseURL: self.baseURL,
            storeDesciption: storeDescriptionPrivate)

        // Shared storeDesciption
        guard let storeDescriptionShared = storeDescriptionPrivate.copy() as? NSPersistentStoreDescription else {
            fatalError("#\(#function): Copying the private store description for a shared one returned an unexpected value.")
        }
        self.storeMap[CKDatabase.Scope.shared] = StoreBundle(
            scope: CKDatabase.Scope.shared,
            baseURL: self.baseURL,
            storeDesciption: storeDescriptionShared)
        container.persistentStoreDescriptions.append(storeDescriptionShared)

        // Public storeDescription
        guard let storeDescriptionPublic = storeDescriptionPrivate.copy() as? NSPersistentStoreDescription else {
            fatalError("#\(#function): Copying the private store description for a public one returned an unexpected value.")
        }
        self.storeMap[CKDatabase.Scope.public] = StoreBundle(
            scope: CKDatabase.Scope.public,
            baseURL: self.baseURL,
            storeDesciption: storeDescriptionPublic)
        container.persistentStoreDescriptions.append(storeDescriptionPublic)

        //
        // Initialize the container
        //
        container.loadPersistentStores { (loadedStoreDescription, error) in
            guard error == nil
            else { fatalError("#\(#function): Failed to load persistent stores:\(error!)") }

            guard let cloudKitContainerOptions = loadedStoreDescription.cloudKitContainerOptions
            else { return }

            guard let bundle = self.storeMap[cloudKitContainerOptions.databaseScope]
            else { fatalError ("#\(#function): Failed to map store for \(cloudKitContainerOptions.databaseScope.name):\(error!)") }

            bundle.store = self.container.persistentStoreCoordinator.persistentStore (for: loadedStoreDescription.url!)
        }

#if InitializeCloudKitSchema
        // Run initializeCloudKitSchema() once to update the CloudKit schema every time you change the Core Data model.
        // Don't call this code in the production environment.
        do {
            try _container.initializeCloudKitSchema()
        } catch {
            print("\(#function): initializeCloudKitSchema: \(error)")
        }
#else

        // container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump // NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = PersistenceController.transactionAuthor

        // Automatically merge the changes from other contexts.
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Pin the viewContext to the current generation token and set it to keep itself up-to-date with local changes.
        //        do {
        //            try container.viewContext.setQueryGenerationFrom(.current)
        //        } catch {
        //            fatalError("#\(#function): Failed to pin viewContext to the current generation:\(error)")
        //        }

        // Observe the following notifications:
        //   - The remote change notifications from container.persistentStoreCoordinator.
        //   - The .NSManagedObjectContextDidSave notifications from any context.
        //   - The event change notifications from the container.
        NotificationCenter.default.addObserver (self,
                                                selector: #selector(storeRemoteChange(_:)),
                                                name: .NSPersistentStoreRemoteChange,
                                                object: container.persistentStoreCoordinator)

        NotificationCenter.default.addObserver (self,
                                                selector: #selector(containerEventChanged(_:)),
                                                name: NSPersistentCloudKitContainer.eventChangedNotification,
                                                object: container)
#endif
    }

    lazy var cloudKitContainer: CKContainer = {
        return CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
    }()

    //
    //
    //
    var shareMap = [League:CKShare]()

    func associate (league: League, share: CKShare) {
        shareMap[league] = share
    }

    func lookupShareFor (league: League) -> CKShare? {
        return shareMap[league]
    }

    var participantMap = [Player:CKShare.Participant]()
    var playerMap      = [CKShare.Participant:Player]()

    func associate (player: Player, participant: CKShare.Participant) {
        participantMap[player] = participant
        playerMap[participant] = player
    }

    // Needs League:Share - 'participant' differs
    func lookupParticipantFor (player: Player) -> CKShare.Participant? {
        return participantMap[player]
    }

    func lookupPlayerFor (participant: CKShare.Participant) -> Player? {
        return playerMap[participant]
    }

    lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()


    /**
     Track the last history tokens for the stores.
     The historyQueue reads the token when executing operations, and updates it after completing the processing.
     Access this user default from the history queue.
     */
    private func historyToken(with storeUUID: String) -> NSPersistentHistoryToken? {
        let key = "HistoryToken" + storeUUID
        if let data = UserDefaults.standard.data(forKey: key) {
            return  try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        return nil
    }

    private func updateHistoryToken(with storeUUID: String, newToken: NSPersistentHistoryToken) {
        let key = "HistoryToken" + storeUUID
        let data = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: key)
    }

}

extension NSPersistentCloudKitContainer {
    func newTaskContext() -> NSManagedObjectContext {
        let context = newBackgroundContext()
        context.transactionAuthor = PersistenceController.transactionAuthor
        return context
    }
}

extension PersistenceController {
    /**
     Handle .NSPersistentStoreRemoteChange notifications.
     Process persistent history to merge relevant changes to the context, and deduplicate the tags, if necessary.
     */
    @objc
    func storeRemoteChange(_ notification: Notification) {
        print ("\nJKP:\nJKP: \(#function): Got: \(notification.description)")

        guard let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String
        else { 
            print("JKP: \(#function): Ignore a notification; no NSStoreUUIDKey.\nJKP:")
            return
        }

        guard storeFor (scope: .private).identifier == storeUUID ||
                storeFor(scope: .shared).identifier == storeUUID
        else {
            print("JKP: \(#function): Ignore a notification; irrelevant store.\nJKP:")
            return
        }

        print("JKP: \(#function): Process history for \(storeUUID)")

        // Processing history
        processHistoryAsynchronously (store: storeFor(uuid: storeUUID)!)

#if false
        queue.addOperation {
            let context = self.container.newTaskContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.performAndWait {

                // self.performHistoryProcessing(storeUUID: storeUUID, performingContext: context)
                let request = self.requestForHistory (storeUUID: storeUUID)

                // Execute the request
                let result = (try? context.execute(request)) as? NSPersistentHistoryResult
                guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else {
                    return
                }
                print("JKP: \(#function): Process transactions: \(transactions.count)\nJKP:")

                // Handle transaction by transaction
                for transaction in transactions {
                    print("JKP: \(#function): Process transaction changes: \(transaction.changes.map(\.count) ?? 0)\nJKP:")
                    for change in transaction.changes ?? [] {
                        print("JKP: \(#function): Process transaction changes each:: \(change)\nJKP:")

                    }
                }
            }
        }
#endif

//        processHistoryAsynchronously(storeUUID: storeUUID)
    }

    private func processHistoryAsynchronously (store: NSPersistentStore) {
        queue.addOperation {
            let context = self.container.newTaskContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.performAndWait {

                // self.performHistoryProcessing(storeUUID: storeUUID, performingContext: context)
                let request = self.requestForHistory (store: store)

                // Execute the request
                let result = (try? context.execute(request)) as? NSPersistentHistoryResult
                guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else {
                    return
                }

                if !transactions.isEmpty {
                    print("JKP: \(#function): Process transactions: \(transactions.count)")
                }

                // Handle transaction by transaction
                for transaction in transactions where transaction.changes != nil {
                    print("JKP:    Process transaction author : \(transaction.author ?? "<none>")")
                    print("JKP:    Process transaction changes: \(transaction.changes.map(\.count) ?? 0)")
                    for change in transaction.changes! {
                        print("JKP:        Process transaction changes each: \(change)")
                        switch change.changeType {
                        case .insert:
                            break
                        case .update:
                            break
                        case .delete:
                            break
                        @unknown default:
                            preconditionFailure("Missed `changeType` case")
                        }
                        // Find the objects that have changed
                    }
                }

                if let token = transactions.last?.token {
                    self.updateHistoryToken(with: store.identifier, newToken: token)
                }

                print ("JKP:\nJKP:")

#if false
                var newTagObjectIDs = [NSManagedObjectID]()
                let tagEntityName = Tag.entity().name

                for transaction in transactions where transaction.changes != nil {
                    for change in transaction.changes! {
                        // Somebody create a new 'tag'
                        if change.changedObjectID.entity.name == tagEntityName && change.changeType == .insert {
                            newTagObjectIDs.append(change.changedObjectID)
                        }
                    }
                }
                if !newTagObjectIDs.isEmpty {
                    deduplicateAndWait(tagObjectIDs: newTagObjectIDs)
                }
#endif
            }
        }
    }


    /**
     Handle the container's event change notifications (NSPersistentCloudKitContainer.eventChangedNotification).
     */
    @objc
    func containerEventChanged(_ notification: Notification) {
        print ("\nJKP:\nJKP: \(#function): Got: \(notification.description)\nJKP:\n")

        guard let value = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey],
              let event = value as? NSPersistentCloudKitContainer.Event else {
            print("JKP: \(#function): Failed to retrieve the container event from notification.userInfo.\nJKP:\n")
            return
        }

        if let error = event.error
        {
            print("JKP: \(#function): Error: \(error.localizedDescription).\nJKP:\n")
            return
        }

        guard let container = notification.object as? NSPersistentCloudKitContainer
        else {
            print("JKP: \(#function): Missed Container: \(notification.object.debugDescription).\nJKP:\n")
            return
        }

        switch event.type {
        case .setup:  break
        case .import: break
        case .export: break
        @unknown default: break
        }

        try? container.fetchShares(in: nil)
            .forEach { share in
                print ("JKP:\nJKP: \(#function): Share (\(share.recordID.zoneID.zoneName)) Participants: \(share.participants.map { $0.userIdentity.nameComponents!.formatted() }.joined(separator: ", "))")
            }

        print("JKP: \(#function): Received a persistent CloudKit container event changed notification.\n\(event)\nJKP:\n")
    }


    func requestForHistory (store: NSPersistentStore) -> NSPersistentHistoryChangeRequest {
        let request = NSPersistentHistoryChangeRequest.fetchHistory (after: historyToken (with: store.identifier))

        // Set the `fetchRequest` to get 'out' transactions
        let requestForTransactionHistory = NSPersistentHistoryTransaction.fetchRequest!
        requestForTransactionHistory.predicate = NSPredicate (value: true)

        //historyFetchRequest.predicate = NSPredicate(format: "author != %@", TransactionAuthor.app)

        request.fetchRequest   = requestForTransactionHistory
        request.affectedStores = [store]
        return request
    }
    /**
     An operation queue for handling history-processing tasks: watching changes, deduplicating tags, and triggering UI updates, if needed.
     */
#if false

    /**
     Process persistent history, posting any relevant transactions to the current view.
     This method processes the new history since the last history token, and is simply a fetch if there's no new history.
     */
    private func processHistoryAsynchronously(storeUUID: String) {
        historyQueue.addOperation {
            let taskContext = self.persistentContainer.newTaskContext()
            taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            taskContext.performAndWait {
                self.performHistoryProcessing(storeUUID: storeUUID, performingContext: taskContext)
            }
        }
    }

    private func performHistoryProcessing(storeUUID: String, performingContext: NSManagedObjectContext) {
        /**
         Fetch the history by the other author since the last timestamp.
         */
        let lastHistoryToken = historyToken(with: storeUUID)
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastHistoryToken)
        let historyFetchRequest = NSPersistentHistoryTransaction.fetchRequest!
        historyFetchRequest.predicate = NSPredicate(format: "author != %@", TransactionAuthor.app)
        request.fetchRequest = historyFetchRequest

        if privatePersistentStore.identifier == storeUUID {
            request.affectedStores = [privatePersistentStore]
        } else if sharedPersistentStore.identifier == storeUUID {
            request.affectedStores = [sharedPersistentStore]
        }

        let result = (try? performingContext.execute(request)) as? NSPersistentHistoryResult
        guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else {
            return
        }
        // print("\(#function): Processing transactions: \(transactions.count).")

        /**
         Post transactions so observers can update the UI, if necessary, even when transactions is empty
         because when a share changes, Core Data triggers a store remote change notification with no transaction.
         */
        let userInfo: [String: Any] = [UserInfoKey.storeUUID: storeUUID, UserInfoKey.transactions: transactions]
        NotificationCenter.default.post(name: PersistenceController.storeDidChangeName, object: self, userInfo: userInfo)
        /**
         Update the history token using the last transaction. The last transaction has the latest token.
         */
        if let newToken = transactions.last?.token {
            updateHistoryToken(with: storeUUID, newToken: newToken)
        }

        /**
         Limit to the private store so only owners can deduplicate the tags. Owners have full access to the private database, and so
         don't need to worry about the permissions.
         */
        guard !transactions.isEmpty, storeUUID == privatePersistentStore.identifier else {
            return
        }
        /**
         Deduplicate the new tags.
         This only deduplicates the tags that aren't shared or have the same share.
         */
        var newTagObjectIDs = [NSManagedObjectID]()
        let tagEntityName = Tag.entity().name

        for transaction in transactions where transaction.changes != nil {
            for change in transaction.changes! {
                if change.changedObjectID.entity.name == tagEntityName && change.changeType == .insert {
                    newTagObjectIDs.append(change.changedObjectID)
                }
            }
        }
        if !newTagObjectIDs.isEmpty {
            deduplicateAndWait(tagObjectIDs: newTagObjectIDs)
        }
    }

    /**
     Track the last history tokens for the stores.
     The historyQueue reads the token when executing operations, and updates it after completing the processing.
     Access this user default from the history queue.
     */
    private func historyToken(with storeUUID: String) -> NSPersistentHistoryToken? {
        let key = "HistoryToken" + storeUUID
        if let data = UserDefaults.standard.data(forKey: key) {
            return  try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        return nil
    }

    private func updateHistoryToken(with storeUUID: String, newToken: NSPersistentHistoryToken) {
        let key = "HistoryToken" + storeUUID
        let data = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: key)
    }
#endif
}

import Combine

extension NotificationCenter {
    var storeDidChangePublisher: Publishers.ReceiveOn<NotificationCenter.Publisher, DispatchQueue> {
        return publisher (for: PersistenceController.storeDidChangeName)
            .receive (on: DispatchQueue.main)
    }
}

///
/// Allow for CoreData encoding of PersonNameComponents
///
@objc (PersonNameComponentsValueTransformer)
final class PersonNameComponentsValueTransformer: NSSecureUnarchiveFromDataTransformer {
    override class var allowedTopLevelClasses: [AnyClass] {
        return [NSPersonNameComponents.self]
    }
    
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override class func valueTransformerNames() -> [NSValueTransformerName] {
        return [name]
    }
    
    static let name = NSValueTransformerName(rawValue: String (describing: PersonNameComponentsValueTransformer.self))
}

extension NSValueTransformerName {
    static let classNameTransformerName = NSValueTransformerName(rawValue: "ClassNameTransformer")
    static let ignore:Void = {
        ValueTransformer.setValueTransformer(
            PersonNameComponentsValueTransformer(),
            forName: PersonNameComponentsValueTransformer.name)
    }()
}
