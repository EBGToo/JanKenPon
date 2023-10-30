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
// share the league with them... there player name, etc gets updated.

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

    @StateObject private var userBox = PlayerBox()
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
            if let user = userBox.player {
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
                    userBox.player = await JanKenPonApp.establishUser (PersistenceController.shared)
                }
            }
        }
#endif
    }

    static let userUUIDKey: String = PersistenceController.bundleIdentifier + ".UserUUID"

    static func establishUser (_ controller: PersistenceController) async -> Player? {

        if let userUUID = UserDefaults.standard.string (forKey: userUUIDKey),
           let user = Player.lookupBy(controller.context, uuid:  UUID (uuidString: userUUID)!) {
            return user
        }

        let container = controller.cloudKitContainer

        do {
            let userID       = try await container.userRecordID ()
            let userRecord   = try await container.publicCloudDatabase.record (for: userID)

            let userDiscoverability = try await container.requestApplicationPermission (
                CKContainer.ApplicationPermissions.userDiscoverability)

            guard .granted == userDiscoverability
            else {
                print ("\(#function) discoverability: \(userDiscoverability.rawValue)")
                return nil
            }

            guard let userIdentity = try await container.userIdentity (forUserRecordID: userRecord.recordID)
            else {
                return nil
            }

            let user = Player.create (controller.context, name: userIdentity.nameComponents!)
            try! controller.context.save()

            UserDefaults.standard.setValue(user.uuid.uuidString, forKey: userUUIDKey)
            return user

            // Get player; if there is one
//            if let user = try await loadUser(record: userRecord) {
//                // Move to the next state
//                await MainActor.run {
//                    self.user  = user
//                    self.state = .establishedUser (user)
//                    refresh()
//                }
//            }
        }
        catch {
            print ("\(#function) error: \(error.localizedDescription)")
            return nil
        }

//        let user = Player.create(context, name: <#T##PersonNameComponents#>)

    }
}

