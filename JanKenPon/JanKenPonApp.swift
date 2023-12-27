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
    var window: UIWindow?

    //
    // Accept the share - requires adding 'CKSharingSupported: YES' to Info.plist
    //
    func windowScene (_ windowScene: UIWindowScene,
                      userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        print ("\(#function): Got userDidAcceptCloudKitShareWith: \(cloudKitShareMetadata.description)")

        let controller = PersistenceController.shared
        let store      = controller.storeFor (scope: .shared)
        let container  = controller.container

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

    func application (_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = JanKenPonSceneDelegate.self
        return configuration
    }
}


@main
struct JanKenPonApp: App {
    // Use the custom AppDelegate class
    // as the app's application delegate.
    @UIApplicationDelegateAdaptor var appDelegate: JanKenPonAppDelegate

    @StateObject private var userBox = UserBox()
    //: Player = JanKenPon.establishUser (PersistenceController.shared)

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
                    // Perhas return an enum w/ 'intermediate state' so the UI can be updated w/
                    // 'establish user', or 'retrying user' or 'awaiting User' or somethinbg
                    userBox.user = await JanKenPonApp.establishUser (PersistenceController.shared)
                }
            }
        }
#endif
    }

    static func establishUser (_ controller: PersistenceController) async -> User? {
        let userUUIDKey   = "userUUID"
        let userContainer = controller.cloudKitContainer
        let userDatabase  = userContainer.publicCloudDatabase

        do {
            // Get the `userRecord` from the publicCloudDatabase
            let userID       = try await userContainer.userRecordID ()
            let userRecord   = try await userDatabase.record (for: userID)

            // If the `userRecord` does not have a `userUUIDKey` then we must create a new `User`.
            // To create a `User` we'll need the `userIdentity`
            if nil == userRecord[userUUIDKey] {
#if false
                let userStatus = try await userContainer.accountStatus()

                guard userStatus == .available
                else {
                    print ("\(#function) accountStatus: \(userStatus)")
                    return nil
                }

                // Find the partcipant for `userID`
                let userParticipant = try await userContainer.shareParticipant (forUserRecordID: userID)
                let userIdentity    = userParticipant.userIdentity

                guard let userName = userIdentity.nameComponents
                else {
                    return nil
                }

#else
                // Request `userDiscoverability`
                let userDiscoverability = try await userContainer.requestApplicationPermission (
                    CKContainer.ApplicationPermissions.userDiscoverability)

                guard .granted == userDiscoverability
                else {
                    print ("\(#function) discoverability: \(userDiscoverability.rawValue)")
                    return nil  // return EstablishUserError.discoverability
                }

                // If discoverable, get the `userIdentity`
                guard let userIdentity = try await userContainer.userIdentity (forUserRecordID: userRecord.recordID),
                      let userName     = userIdentity.nameComponents
                else {
                    return nil // return EstablishUserError.userIdentity
                }
#endif
                // Create `newUser` with the `userRecordId`.  We'll use this to lookup the
                // Core Data User.
                let newUser = User.create (controller.context,
                                           name: userName,
                                           recordID: userIdentity.userRecordID!.recordName)

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

            // Lookup the existing user with the permanent `userManagedObjectID`.  If the
            // publicDatabase has not been synced w/ the local CoreData, such as when a new device
            // starts the app for the first time or an old device has been wiped, then `user` will
            // not exist - we'd need to wait until the import is done.
            guard let user = User.lookupBy(controller.context, uuid: userUUID)
            else {
                // "If the context recognizes the specified object, the method returns that object.
                //  Otherwise, the context fetches and returns a fully realized object from the
                //  persistent store; unlike object(with:), this method never returns a fault. If
                //  the object doesn’t exist in both the context and the persistent store, the
                //  method throws an error."
                //
                // If thrown, our `try?` produces `nil` and we'll need to wait.
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

