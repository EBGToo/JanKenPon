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

    static let storeDidChange       = Notification.Name("jankenponStoreDidChange")
    static let relevantTransactions = Notification.Name("relevantTransactions")

    static let transactionAuthor = "What the Heck is This?"  // Another App is updating the transaction history?

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

    lazy var cloudKitContainer: CKContainer = {
        return CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
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

        // Reconstruct the share map

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

//        NotificationCenter.default.addObserver (self,
//                                                selector: #selector(containerEventChanged(_:)),
//                                                name: NSPersistentCloudKitContainer.eventChangedNotification,
//                                                object: container)
#endif
    }

    //
    //
    //
    var shareMap = [League:CKShare]()

    func associate (league: League, share: CKShare) {
        shareMap[league] = share
    }

    func lookupLeagueFor (share: CKShare) -> League? {
        return shareMap.first { $0.1 == share }.flatMap { $0.0 }
    }

    func lookupShareFor (league: League) -> CKShare? {
        return shareMap[league]
    }

    func deleteShareFor (league: League) async {
        guard let share = shareMap[league]
        else { return }

        // "CloudKit deletes the share if the owner of the shared heirarchy deletes its root record"
        //
        // What about the share's zone?
        if let zones = try? await cloudKitContainer.privateCloudDatabase.allRecordZones(),
           let zoneToDelete = zones.first (where: { zoneRecord in
               share.recordID.zoneID == zoneRecord.zoneID
           }) {
            let _ = try? await cloudKitContainer.privateCloudDatabase.deleteRecordZone(withID: zoneToDelete.zoneID)
        }

        shareMap.removeValue(forKey: league)
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

        //print("JKP: Transaction history")

        // self.performHistoryProcessing(storeUUID: storeUUID, performingContext: context)
        let request = self.requestForHistoryTransactions (store: store)

        let transactions = self.fetchHistoryTransactions (context,
                                                          request: request,
                                                          keepIfTrue: { $0.changes != nil })

        Task {
            //                    NotificationCenter.default.post (name: .didFindRelevantTransactions,
            //                                                     object: self,
            //                                                     userInfo: ["transactions": transactions])
        }

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



        // Handle each of transactions independently.  A Massive Assumption - Deduplicate
        transactions.forEach { self.processHistoryTransaction (context, $0) }

        // Update our history token
        if let token = transactions.last?.token {
            self.updateHistoryToken(with: store.identifier, newToken: token)
        }
    }

    private func processHistoryTransaction (_ context: NSManagedObjectContext, 
                                            _ transaction: NSPersistentHistoryTransaction ) {
        print("JKP:    Transaction author : \(transaction.author ?? "<none>")")
        print("JKP:    Transaction changes: \(transaction.changes.map(\.count) ?? 0)")
        transaction.changes?.forEach { self.processHistoryTransactionChange (context, $0) }
    }

    private func processHistoryTransactionChange (_ context: NSManagedObjectContext, 
                                                  _ change: NSPersistentHistoryChange) {
        print("JKP:        Transaction change : \(change)")

        // Process changes based on the entity type
        switch change.changedObjectID.entity.name {
        case Game.entity().name:
            break

        case League.entity().name:
            guard let league = context.object (with: change.changedObjectID) as? League
            else { preconditionFailure() }

            processHistoryTransactionChangeLeague (context, change, league)

        case Move.entity().name:
            break

        case Player.entity().name:
            guard let player = context.object (with: change.changedObjectID) as? Player
            else { preconditionFailure() }

            processHistoryTransactionChangePlayer (context, change, player)

        case Round.entity().name:
            break

        case User.entity().name:
            guard let user = context.object (with: change.changedObjectID) as? User
            else { preconditionFailure() }

            processHistoryTransactionChangeUser (context, change, user)

        default:
            preconditionFailure ("Unknown entity-type in transaction change")
        }
    }

    private func processHistoryTransactionChangeLeague (_ context: NSManagedObjectContext, 
                                                        _ change: NSPersistentHistoryChange,
                                                        _ league: League) {
        print("JKP:        Transaction change league: \(change.changeType)")
        switch change.changeType {
        case .insert:
            break
        case .update:
            break
        default:
            break
        }
        //        for change in transaction.changes! {
        //            switch change.changeType {
        //            case .insert:
        //                break
        //            case .update:
        //                break
        //            case .delete:
        //                break
        //            @unknown default:
        //                preconditionFailure("Missed `changeType` case")
        //            }
        //            // Find the objects that have changed
        //        }
    }

    private func processHistoryTransactionChangePlayer(_ context: NSManagedObjectContext, 
                                                       _ change: NSPersistentHistoryChange,
                                                       _ player: Player) {
        print("JKP:        Transaction change player: \(change.changeType)")
    }

    private func processHistoryTransactionChangeUser (_ context: NSManagedObjectContext,
                                                      _ change: NSPersistentHistoryChange, 
                                                      _ user: User) {
        print("JKP:        Transaction change user  : \(change.changeType)")
    }


    /**
     Handle the container's event change notifications (NSPersistentCloudKitContainer.eventChangedNotification).
     */
    @objc
    func containerEventChanged(_ notification: Notification) {
        print ("JKP:\nJKP: \(#function): Got: \(notification.description).")

        guard let value = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey],
              let event = value as? NSPersistentCloudKitContainer.Event else {
            print("JKP: \(#function): Failed to retrieve the container event from notification.userInfo.")
            return
        }

        if let error = event.error
        {
            print("JKP: \(#function): Error: \(error.localizedDescription).")
            return
        }

        guard let container = notification.object as? NSPersistentCloudKitContainer
        else {
            print("JKP: \(#function): Missed Container: \(notification.object.debugDescription).")
            return
        }

        switch event.type {
        case .setup:  break
        case .import:
            // Once an import is successful, fetch the particpants and add any that are
            // not currently users.
            if event.succeeded {
                Task {
                    do {
                        var needContextSave = false

                        // Get all the shares
                        let shares = try container.fetchShares (in: nil)

                        // Map each share to its pre-existing league
                        let shareToExistingLeagueMap = shares.reduce (into: [CKShare:League]()) { result, share in
                            if let league = lookupLeagueFor(share: share) {
                                result[share] = league
                            }
                        }

                        // Find shares w/o a League
                        let unknownShares = shares.filter { nil == shareToExistingLeagueMap[$0] }

                        //


                        let shareToUnknownLeagueMap = try await cloudKitContainer.shareMetadatas(for: shares.map { $0.url! })
                            .reduce(into: [CKShare:League]()) { result, entry in
                                let (shareURL, shareMetadataResult) = entry
                                
                                switch shareMetadataResult {
                                case .success(let metadata):
                                    guard let share = shares.first (where: { share in shareURL == share.url })
                                    else { preconditionFailure() }

                                    if let leagueRecord = metadata.rootRecord,
                                       let leagueUUID   = (leagueRecord["CD_moUUID"] as? String).flatMap ({ UUID(uuidString: $0) }),
                                       let league       = League.lookupBy (self.context, uuid: leagueUUID) {
                                        result [share] = league
                                    }

                                case .failure(let error):
                                    break
                                }
                            }

                        let shareToLeagueMap = shareToExistingLeagueMap
                            .merging (shareToUnknownLeagueMap,
                                      uniquingKeysWith: { existing, unknown in existing })

                        // ****************************
                        // DO ALL OF THIS IN 'CREATE LEAGUE' (storeRemoteChange).  THEN WE SURELY
                        // HAVE A `LEAGUE' AND A 'SHARE' - NO MUCKING WITH CKRECORD.
                        //
                        // HOW DOES 'REMOTE ACCEPT' TRIGGER THAT??
                        // ****************************

                        // Get each shares metadata


                        for share in shares {
                            //
                            // This share is associated w/ one-and-only-one league.  We can't use the
                            // shareMap to find this share's league because this share might be new to
                            // us - as in we accepted the invite.  We need to find the root record
                            //
                            guard let league = shareToLeagueMap[share]
                            else {
                                return
                            }

                            // Map the userRecordID?.record name to the participant
                            let participantMap = share.participants
                                .reduce (into: Dictionary<String, CKShare.Participant>()) { result, participant in
                                    if .owner != participant.role, let recordIdentiter = participant.userIdentity.userRecordID?.recordName {
                                        result[recordIdentiter] = participant
                                    }
                                }

                            // Every participant must have a User.  Create new Users if needed.
                            let users = participantMap.map { participantMapEnty in
                                let (recordIdentifier, participant) = participantMapEnty

                                // See if we already have a User with `recordIdentifer`.  If not create one
                                if let user = User.lookupBy (context, recordID: recordIdentifier) {
                                    return user
                                }
                                else {
                                    let userIdentity = participant.userIdentity
                                    let userInfo     = userIdentity.lookupInfo
                                    let userRecordID = userInfo?.userRecordID?.recordName
                                    let userName     = (userIdentity.nameComponents
                                                        ?? PersonNameComponents (
                                                            givenName:  "",
                                                            familyName: userRecordID  ?? "Unknown"))

                                    print ("JKP: \(#function): User: \(userName.formatted())")
                                    needContextSave = true

                                    // Create the new User
                                    return User.create (context,
                                                        scope: (userIdentity.hasiCloudAccount ? .user : .player),
                                                        name:         userName,
                                                        phoneNumber:  userInfo?.phoneNumber,
                                                        emailAddress: userInfo?.emailAddress,
                                                        recordID:     userRecordID)
                                }
                            }

                            //
                            // We need one league player for every User
                            //

                            let usersMissingAPlayer = users.filter { user in
                                return !league.players.contains { player in
                                    player.hasUser (user)
                                }
                            }

                            for missedUser in usersMissingAPlayer {
                                league.addPlayer (Player.create (context, user: missedUser))
                            }

                            // A participant might have just now accepted (and we created a User) or
                            // have accepted for a prior share (we already had a User).

                            //
                        }
                        if needContextSave {
                            try context.performAndWait {
                                try context.save()
                            }
                        }
                    }
                    catch {
                        print("JKP: \(#function): Identify Users Error: \(error.localizedDescription).")
                    }
                }
            }
        case .export: break
        @unknown default: break
        }

        print("JKP: \(#function): Done")
    }


    func requestForHistoryTransactions (store: NSPersistentStore) -> NSPersistentHistoryChangeRequest {
        let request = NSPersistentHistoryChangeRequest.fetchHistory (after: historyToken (with: store.identifier))

        // Set the `fetchRequest` to get 'out' transactions
        let requestForTransactionHistory = NSPersistentHistoryTransaction.fetchRequest!
        //requestForTransactionHistory.predicate = NSPredicate (value: true)
        requestForTransactionHistory.predicate = NSPredicate (format: "author != %@", PersistenceController.transactionAuthor)

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
        NotificationCenter.default.post(name: PersistenceController.storeDidChange, object: self, userInfo: userInfo)
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
        return publisher (for: PersistenceController.storeDidChange)
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
