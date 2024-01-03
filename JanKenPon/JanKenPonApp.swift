//
//  JanKenPonApp.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import SwiftUI
import CloudKit
import CoreData

//
// https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/accepting_share_invitations_in_a_swiftui_app
//

// Create a league and then share it - everybody who accepts the share joins the league
// and can then participate in games, as a player and creator.
//
// There would need to be other players added (in the AG Scoring App case).  Create them and then
// share the league with them... their player name, etc gets updated.


class JanKenPonSceneDelegate: UIResponder, UIWindowSceneDelegate {
    //
    // Accept the share - requires adding 'CKSharingSupported: YES' to Info.plist
    //
    func windowScene (_ windowScene: UIWindowScene,
                      userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        print ("\(#function): Got userDidAcceptCloudKitShareWith: \(cloudKitShareMetadata.description)")

        let controller = PersistenceController.shared
        let store      = controller.storeFor (scope: .shared)
        let container  = controller.container

        // Where is the 'share' and the 'league'?
        
        container.acceptShareInvitations(from: [cloudKitShareMetadata], into: store) { (_, error) in
            if let error = error {
                print("\(#function): Failed to accept share invitations: \(error)")
            }
        }
    }
}

class JanKenPonAppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    func application (_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting
                     connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {

        // Create a scene configuration object for the specified session role.
        let config = UISceneConfiguration (name: nil, // "Default Configuration"
                                           sessionRole: connectingSceneSession.role)

        // Set the configuration's delegate class to the scene delegate that implements the
        // share acceptance method.
        config.delegateClass = JanKenPonSceneDelegate.self

        return config
    }
}


@main
struct JanKenPonApp: App {
    // Use the custom AppDelegate class as the app's application delegate.
    @UIApplicationDelegateAdaptor var appDelegate: JanKenPonAppDelegate

    @StateObject private var userBox = UserBox()
    @State private var needEstablishUserAlert = false

    var body: some Scene {
#if InitializeCloudKitSchema
        WindowGroup {
            Text("Initializing CloudKit Schema...").font(.title)
            Text("Stop after Xcode says 'no more requests to execute', " +
                 "then check with CloudKit Console if the schema is created correctly.").padding()
        }
#else
        WindowGroup {
            if let user = userBox.user {
                ContentView()
                    .environmentObject (PersistenceController.shared)
                    .environmentObject (user)
                    .environment(\.managedObjectContext, PersistenceController.shared.context)
            }
            else {
                VStack {
                    Spacer()
                    Text ("Establishing User...")
                    Spacer()
                }
                .task {
                    // Perhaps return an enum w/ 'intermediate state' so the UI can be updated w/
                    // 'establish user', or 'retrying user' or 'awaiting User' or somethinbg
                    var retries = 3
                    while .none == userBox.user && retries > 0 {
                        print ("JKP: User: Establish Tries Remaining: \(retries)")
                        userBox.user = await JanKenPonApp.establishUser (PersistenceController.shared)
                        retries -= 1
                    }

                    print ("JKP: User: \(userBox.user.map (\.fullname) ?? "MISSED")")
                    needEstablishUserAlert = (.none == userBox.user)
                }
                .alert("""
                            Unable to establish the App user.  Please quit the App, ensure network \
                            connectivity and then retry.
                            """,
                       isPresented: $needEstablishUserAlert) {
                    Button ("Quit") { exit(EXIT_SUCCESS) }
                }
            }
        }
#endif
    }

    
    ///
    /// Establish the User
    ///
    /// A User is the top-level object in this App.  It is the user's leagues and games that are
    /// presented and acted-upon in the UI.  A `User` is passed as an `@EnvironmentObject` through
    /// SwiftUI.
    ///
    /// A User is a NSManagedObject that is stored in the CoreData container's private database.
    /// The User is NEVER referenced by another object type, such as a Player or League, what will
    /// be shared.  Per CoreData, any object that is shared is moved to a 'share' and all
    /// referenced objects are moved into the 'share' to.  The `User` object is designed not
    /// to be shared precisely so that it can refer to the leagues and players that must be shared.
    ///
    /// The CloudKit interface has a `User` record that appears in the public database.  While
    /// this record is accessible, the interfaces to get user identity information are 1) dependent
    /// on the User allowing access and 2) deprecated.  The seemingly only approved method is to
    /// create a share and then look at the `participants`.  A share is created when asking others
    /// to use the App and thus one must implicitly identify one's self; having done that, the App
    /// can get the identity information.
    ///
    /// As we want to establish a User early we'd need to create a share, even if a throw-away
    /// share, and then get the sole participant.  Problem is that there appears to be a racy-
    /// condition between CoreData and CloudKit.  CoreData creates the object and schedules it for
    /// saving in CloudKit; creating the share goes to get the share's object to move it into the
    /// shared zone, but the object isn't there.  Thankfully the SwiftUI need not SHOW the User
    /// identity information until an actual share is needed.
    ///
    /// We'll create a User immediately but be willing to leave the identity information (name,
    /// phoneNumber, emailAddress) empty.  Later when the share is created we'll use the particpant
    /// userLookup to fill out User.  This sort of think needs to be done anyway are other Users
    /// accept invitations.
    ///
    /// - Parameter controller: the NSManagedObject controller
    ///
    /// - Returns: A `User`, if possible
    ///
    static func establishUser (_ controller: PersistenceController) async -> User? {
        let userUUIDKey   = "userUUID"
        let userContainer = controller.cloudKitContainer
        let userDatabase  = userContainer.publicCloudDatabase
        var userIdentity  = Optional<CKUserIdentity>.none

        do {

            //
            // We'll store the UUID of the CoreData `User` in the CloudKit `User` record.  If there
            // is no UUID in CloudKit, then this will be the first time the User has ever started
            // the App.  We'll create a user and update the CloudKit `User` record
            //

            let userID       = try await userContainer.userRecordID ()
            let userRecord   = try await userDatabase.record (for: userID)

            // If the `userRecord` does not have a `userUUIDKey` then we must create a new `User`.
            if nil == userRecord[userUUIDKey] {

                // See if the user has the required iCloud account.
                let userStatus = try await userContainer.accountStatus()

                guard userStatus == .available
                else {
                    print ("\(#function) accountStatus: \(userStatus)")
                    return nil
                }

                //
                // Create a `dummyShare` (in a 'dummyZone') so we can access the share's owner
                // That owner will have our `userIdentity`
                //

                do {
                    let dummyZone     = CKRecordZone (zoneName: UUID().uuidString)
                    let dummyShare    = CKShare (recordZoneID: dummyZone.zoneID)

                    print ("JKP: User: Establish Zone: \(dummyZone.zoneID.zoneName)")

                    // Save the dummyZone and then the dummyShare (for/in the dummyZone)
                    let _ = try await userContainer.privateCloudDatabase.save (dummyZone)
                    let _ = try await userContainer.privateCloudDatabase.save (dummyShare)

                    // Extract the dummyShare's owner's identity - which is 'us/me'
                    userIdentity = dummyShare.owner.userIdentity

                    // Cleanup by deleting the 'dummyShare' and then the 'dummyZone'
                    let _ = try await userContainer.privateCloudDatabase.deleteRecord (withID: dummyShare.recordID)
                    let _ = try await userContainer.privateCloudDatabase.deleteRecordZone (withID: dummyZone.zoneID)
                }
                catch {
                    print ("JKP: User Establish Error: \(error.localizedDescription)")
                }

                // Create `newUser` with the `userRecordId`.  We'll use this to lookup the
                // Core Data User when players appear in a League.
                let newUser = User.create (controller.context,
                                           scope: User.Scope.owner,
                                           name: (userIdentity?.nameComponents ?? User.nameDefault),
                                           recordID: userID.recordName)


                // Save `newUser` to ensure CoreData has the object and, if needed, the object's
                // objectID is a permanent one.
                try controller.context.save ()

                // Confirm the save
                guard !newUser.objectID.isTemporaryID
                else {
                    return nil // return EstablishUserError.objectID
                }

                // Store the newUser's `uuid` back into the `userRecord`.  Then any other device
                // starting this App will find CoreData user with this `uuid'.
                userRecord[userUUIDKey] = newUser.uuid.uuidString

                // Save the updated `userRecord`
                let (savedUserResult, _) = try await userDatabase.modifyRecords (
                    saving: [userRecord],
                    deleting: [],
                    savePolicy: CKModifyRecordsOperation.RecordSavePolicy.ifServerRecordUnchanged,
                    atomically: true)

                // Our savedUserResult will/must have a single entry; examine it for errors
                switch savedUserResult[userRecord.recordID]! {
                case .success(_):
                    return newUser
                case .failure (let error):
                    print ("\(#function) error: \(error.localizedDescription)")
                    return nil
                }
                // Never here
            }

            // Get the `userManagedObjectID` from the `userRecord`
            guard let userUUID = userRecord[userUUIDKey]
                .flatMap ({ UUID(uuidString: $0) })
            else {
                return nil
            }

            //
            // Lookup the existing user with the permanent `userManagedObjectID`.  If the
            // publicDatabase has not been synced w/ the local CoreData, such as when a new device
            // starts the app for the first time or an old device has been wiped, then `user` will
            // not exist - we'd need to wait until the import is done.
            //
            // "The Royal Hack"
            //
            var retries = 10
            while retries > 0, .none == User.lookupBy(controller.context, uuid: userUUID) {
                retries -= 1
                sleep (2)
            }

            guard let user = User.lookupBy(controller.context, uuid: userUUID)
            else {
                // Might be here is the User deletes the local App from their device and then
                // reinstalls and restarts the App.  CloudKit has the data but it has not been
                // reconstructed in CoreData yet.
                //
                // See "The Royal Hack"
                return nil
            }

            // Return the pre-existing `user`
            return user
        }
        catch {
            print ("\(#function) error: \(error.localizedDescription)")
            return nil
        }
    }
}
