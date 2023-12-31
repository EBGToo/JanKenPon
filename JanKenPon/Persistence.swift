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
    struct App {
        static let name = "JanKenPon"
        static let bundleIdentifier = "com.agdogfights.\(name)"
    }

    // Core Data
    struct CoreData {
        static let modelName = "JanKenPon"
        static let storeDidChange       = Notification.Name("\(modelName).storeDidChange")
        static let relevantTransactions = Notification.Name("\(modelName).relevantTransactions")
        static let transactionAuthor = "\(modelName).app"  // Another App is updating the transaction history?
    }

    struct CloudKit {
        static let containerName       = App.name
        static let containerVersion    = "r0001"
        static let containerIdentifier = "iCloud.\(App.bundleIdentifier).\(containerVersion)"
    }

    enum Configuration: String, CustomStringConvertible {
        case `default` = "Default"

        var description: String {
            return self.rawValue
        }
    }

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
                containerIdentifier: PersistenceController.CloudKit.containerIdentifier)
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

    lazy var cloudKitContainer: CKContainer = {
        return CKContainer(identifier: PersistenceController.CloudKit.containerIdentifier)
    }()


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
        self.container = NSPersistentCloudKitContainer (name: PersistenceController.CloudKit.containerName)

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
        container.viewContext.transactionAuthor = PersistenceController.CoreData.transactionAuthor

        // Automatically merge the changes from other contexts.
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Reconstruct the share map

        // Pin the viewContext to the current generation token and set it to keep itself up-to-date with local changes.
        //        do {
        //            try container.viewContext.setQueryGenerationFrom(.current)
        //        } catch {
        //            fatalError("#\(#function): Failed to pin viewContext to the current generation:\(error)")
        //        }

        NotificationCenter.default.addObserver (self,
                                                selector: #selector(storeRemoteChange(_:)),
                                                name: .NSPersistentStoreRemoteChange,
                                                object: container.persistentStoreCoordinator)

#endif
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
        context.transactionAuthor = PersistenceController.CoreData.transactionAuthor
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
        //print ("JKP:")
        //print ("JKP:\nJKP: \(#function): Got: \(notification.description)")

        guard let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String
        else { 
            //print("JKP: \(#function): Ignore a notification; no NSStoreUUIDKey.")
            return
        }

        guard storeFor (scope: .private).identifier == storeUUID ||
                storeFor(scope: .shared).identifier == storeUUID
        else {
            //print("JKP: \(#function): Ignore a notification; irrelevant store.")
            return
        }

        //print("JKP: \(#function): Process history for \(storeUUID).")

        // Processing history
        queue.addOperation {
            let context = self.container.newTaskContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.performAndWait {
                self.processHistory (context: context, store: self.storeFor (uuid: storeUUID)!)
            }
        }
    }

    private func processHistory (context: NSManagedObjectContext, store: NSPersistentStore) {
        let request      = requestForHistoryTransactions (store: store)
        let transactions = fetchHistoryTransactions (context,
                                                     request: request,
                                                     keepIfTrue: { $0.changes != nil })

        Task {
            NotificationCenter.default.post (name: CoreData.relevantTransactions,
                                             object: self,
                                             userInfo: ["transactions": transactions])
        }

        processHistoryUserPlayerAssociation (context, transactions)
        processHistoryUserIdentity(context, transactions)

        // Update our history token
        if let token = transactions.last?.token {
            self.updateHistoryToken(with: store.identifier, newToken: token)
        }
    }

    private func processHistoryUserPlayerAssociation (_ context: NSManagedObjectContext,
                                                      _ transactions: [NSPersistentHistoryTransaction]) {
        //
        // Find leagueObjectIDs that have been updated with changes to moPlayers.  We'll need to
        // ensure proper User <==> Player links.  User's are ALWAYS in the privateDatabase while
        // Player's are ALWAYS in sharedDatabases - part of a League's share.
        //
        let leagueObjectIDs = transactions
            .flatMap { $0.changes ?? [] }
            .filter  { $0.changeType  == .update  }
            .filter  {
                guard let updatedProperties = $0.updatedProperties
                else { return false }

                return updatedProperties.contains {
                    $0.entity.name == League.entity().name &&       // league changed
                    $0.name        == "moPlayers"                   // league players updated
                }
            }
            .map { $0.changedObjectID }
        //            .uniquify

        if !leagueObjectIDs.isEmpty {
            let leagueContext = container.newTaskContext()

            leagueContext.performAndWait {
                // All User's; we'll filter for those missing players
                let allUsersAsOwner = User.all (leagueContext).filter { $0.scope == .owner }

                // My User will be the only one with .owner
                precondition (1 == allUsersAsOwner.count)
                let myUser   = allUsersAsOwner.first!


                // The leages that have player changes
                let leagues = leagueObjectIDs
                    .map { leagueContext.object(with: $0) as! League }

                for league in leagues {
                    // Every league must have my User as a Player.  A league only appears in
                    // my `context` if I have accepted the `share` and am thus in the league.
                    if !league.players.contains (where: { myUser.hasPlayer($0) }) {
                        let player = Player.create (leagueContext, user: myUser)

                        myUser.addPlayer (player)
                        league.addPlayer (player)
                    }

                    // Look at every player in league; we'll resolve User <==> Player references.
                    for player in league.players {

                        if let user = player.user (in: context) {
                            // If the player references an existing user, that user needs to
                            // point back at the player.  Such a link won't exist in a case where
                            // a remote app accepts a SECOND share - the first share acceptance
                            // created the User (see below); the second one will see the user but
                            // won't have a link yet
                            user.addPlayer (player)
                        }
                        else {
                            // If a remote App has accepted a `share`, they will add their player to
                            // this league (see above abvoe).  We won't have a User for that player;
                            // we'll have to create a User, in our privateDatabase
                            let _ = User.create (leagueContext,
                                                 scope: User.Scope.user,
                                                 player: player)
                        }
                    }
                }

                // On 'insert' league players are []; on 'update' players exist
                try? leagueContext.save()
            }
        }
    }

    private func processHistoryUserIdentity (_ context: NSManagedObjectContext,
                                             _ transactions: [NSPersistentHistoryTransaction]) {
    }

    func requestForHistoryTransactions (store: NSPersistentStore) -> NSPersistentHistoryChangeRequest {
        let request = NSPersistentHistoryChangeRequest.fetchHistory (after: historyToken (with: store.identifier))

        // Set the `fetchRequest` to get 'out' transactions
        let requestForTransactionHistory = NSPersistentHistoryTransaction.fetchRequest!
        //requestForTransactionHistory.predicate = NSPredicate (value: true)
        requestForTransactionHistory.predicate = NSPredicate (format: "author != %@", PersistenceController.CoreData.transactionAuthor)

        request.fetchRequest   = requestForTransactionHistory
        request.affectedStores = [store]

        return request
    }

    private func fetchHistoryTransactions (_ context: NSManagedObjectContext,
                                           request: NSPersistentHistoryChangeRequest,
                                           keepIfTrue: ((NSPersistentHistoryTransaction) -> Bool)? = nil) -> [NSPersistentHistoryTransaction] {
        // Execute the request
        let historyResult = (try? context.execute(request)) as? NSPersistentHistoryResult

        // Expect HistoryTransactions
        guard let unfilteredTransactions = historyResult?.result as? [NSPersistentHistoryTransaction]
        else {
            return []
        }

        let transactions = unfilteredTransactions
            .filter { keepIfTrue?($0) ?? true }

        if !unfilteredTransactions.isEmpty {
            print("JKP: Transaction History Fetch: All \(unfilteredTransactions.count), Count \(transactions.count)")
        }

        return transactions
    }
}


import Combine

extension NotificationCenter {
    var storeDidChangePublisher: Publishers.ReceiveOn<NotificationCenter.Publisher, DispatchQueue> {
        return publisher (for: PersistenceController.CoreData.storeDidChange)
            .receive (on: DispatchQueue.main)
    }

    var releventTransactionPublisher: Publishers.ReceiveOn<NotificationCenter.Publisher, DispatchQueue> {
        return publisher (for: PersistenceController.CoreData.relevantTransactions)
            .receive (on: DispatchQueue.main)
    }
}

///
/// Allow for CoreData encoding of PersonNameComponents
///

//@objc (PersonNameComponentsValueTransformer)
//final class PersonNameComponentsValueTransformer: NSSecureUnarchiveFromDataTransformer {
//    override class var allowedTopLevelClasses: [AnyClass] {
//        return [NSPersonNameComponents.self]
//    }
//
//    override class func allowsReverseTransformation() -> Bool {
//        return true
//    }
//
//    override class func valueTransformerNames() -> [NSValueTransformerName] {
//        return [name]
//    }
//
//    static let name = NSValueTransformerName(rawValue: String (describing: PersonNameComponentsValueTransformer.self))
//}

@objc (PersonNameComponentsValueTransformer)
class PersonNameComponentsValueTransformer: NSSecureUnarchiveFromDataTransformer {
    static let name = NSValueTransformerName (rawValue: "PersonNameComponentsValueTransformer")
    override class var allowedTopLevelClasses: [AnyClass] {
        return [NSPersonNameComponents.self]
    }
}

extension NSValueTransformerName {
    static let classNameTransformerName = NSValueTransformerName(rawValue: "ClassNameTransformer")
    static let ignore:Void = {
        ValueTransformer.setValueTransformer(
            PersonNameComponentsValueTransformer(),
            forName: PersonNameComponentsValueTransformer.name)
    }()
}


//@objc(SecureCLLocationTransformer)
//class SecureCLLocationTransformer: NSSecureUnarchiveFromDataTransformer {
//    public static let transformerName = NSValueTransformerName(rawValue: "SecureCLLocationTransformer")
//    override class var allowedTopLevelClasses: [AnyClass] {
//        return [CLLocation.self]
//    }
//}
//
//// MARK: Serialization of UIColor
//@objc(ColorTransformer)
//class ColorTransformer: NSSecureUnarchiveFromDataTransformer {
//    public static let transformerName = NSValueTransformerName(rawValue: "ColorTransformer")
//    override class var allowedTopLevelClasses: [AnyClass] {
//        return [UIColor.self]
//    }
//}
