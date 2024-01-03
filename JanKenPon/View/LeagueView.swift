//
//  LeagueView.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import SwiftUI
import CloudKit
import CoreData

struct LeagueListView: View {
    @Environment(\.managedObjectContext) private var context

    @EnvironmentObject private var controller: PersistenceController
    @EnvironmentObject private var user: User

    @FetchRequest(
        sortDescriptors: [],
        animation: .default)
    private var leagues: FetchedResults<League>

    @State var showCreateLeague: Bool = false
    @State private var createdLeague: League? = nil


    var body: some View {
        NavigationStack {
            List {
                ForEach(leagues.sorted(by: League.byDateSorter)) { league in
                    NavigationLink {
                        LeagueView (league: league)
                    } label: {
                        HStack {
                            Text(league.name)
                            Spacer()
                            Text ("(\(user.leagues.contains(league) ? "Y" : "N")) (O: \(league.owner.fullname))")
                                .font (.footnote)
                        }
                    }
                }
                //                .onDelete(perform: deleteItems)
            }
            .navigationBarTitle("Leagues")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem {
                    Button(action: { showCreateLeague = true },
                           label:  { Label("Create League", systemImage: "plus") })
                }
            }
        }
        .sheet (isPresented: $showCreateLeague) {
            LeagueCreateView (league: $createdLeague) { saved in
                if let league  = createdLeague {
                    try? context.save()
                    doTheShareThing (league: league) {
                        showCreateLeague = false
                    }
                }
                else {
                    showCreateLeague = false
                }
            }
        }
    }

    private func doTheShareThing (league: League, done: @escaping () -> Void) {
        Task {
            do {
                let (_, share, _) = try await controller.container.share ([league], to: nil)

                // Configure the share
                share[CKShare.SystemFieldKey.title] = league.name
            }
            catch {
                print ("JKP: Error: \(error.localizedDescription)")
                print ("JPP: Done")
            }

            done()
        }
    }
}


struct LeagueView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.editMode) private var editMode
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss


    @EnvironmentObject private var controller: PersistenceController
    @EnvironmentObject private var user: User

    public static let dateFormatter: DateFormatter = {
        let formatter:DateFormatter = DateFormatter()
        formatter.dateFormat = "E, d MMM yyyy '@' HH:mm"
        return formatter
    }()

    @ObservedObject var league: League

    @State private var isEditing = false

    @State private var leagueName: String = ""
    @State private var leagueUsers: Set<User> = Set()

    func bindingFor (user: User) -> Binding<Bool> {
        return Binding(
            get: { leagueUsers.contains(user) },
            set: { (on) in
                if on { leagueUsers.insert(user) }
                else  { leagueUsers.remove(user) }
            })
    }

    @State private var playerFamilyName: String = ""
    @State private var playerGivenName: String = ""

    func canCreatePlayer () -> Bool {
        return !playerGivenName.isEmpty && !playerFamilyName.isEmpty
    }

    @FetchRequest(
        sortDescriptors: [], // [NSSortDescriptor(keyPath: \Player.fullname, ascending: true)],
        animation: .default)
    private var users: FetchedResults<User>

    @State private var showCreateGame = false
    @State private var createdGame: Game? = nil

    @State private var showInvitePlayers = false

    @State private var leagueIsDeleted = false

    var body: some View {
        NavigationStack {
            Form {
                if leagueIsDeleted {
                    EmptyView()
                }
                else {
                    Section ("Configuration") {
                        HStack {
                            Text ("name:")
                                .opacity(0.8)
                                .font (.subheadline)
                            if isEditing  { // } editMode?.isEditing {
                                TextField ("required", text: $leagueName)
                                    .multilineTextAlignment(TextAlignment.trailing)
                            }
                            else {
                                Text (leagueName)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }

                    if !isEditing {
                        Section () {
                            Button ("Create Game") {
                                showCreateGame = true
                            }
                            .frame (maxWidth: .infinity)
                        }
                    }

                    Section ("Games") {
                        List (league.games.sorted(by: Game.byDateSorterRev)) { game in
                            NavigationLink {
                                GameView (game: game)
                                    .environmentObject(user.playerInLeague(league)!)
                            } label: {
                                Text (LeagueView.dateFormatter.string(from: game.date))
                            }
                        }
                    }

                    Section ("Owner") {
                        Text ("P: \(league.owner.fullname)")
                            .foregroundStyle (isEditing ? .gray : (colorScheme == .dark ? .white :  .black))
                    }

                    Section ("Players") {
                        //ScrollView {
                        if isEditing {
                            List (users) { user in
                                Toggle ("U: \(user.fullname)", isOn: bindingFor(user: user))
                                    .disabled (self.user == user)

                            }
                        }
                        else {
                            List (Array(league.players)) { player in
                                Text ("P: \(player.fullname)")
                            }
                        }
                        //                    }
                    }

                    Section () {
                        Button ("Invite Players") {
                            showInvitePlayers = true
                        }
                        .frame (maxWidth: .infinity)

                    }
                    if isEditing {
                        Section () {
                            Button ("Delete League", role: .destructive) {
                                leagueIsDeleted = true

                                user.remLeague (league)
                                context.delete (league)
                                try? context.save()

                                dismiss()

                                // Must also delete the 'zone' for league
                            }
                            .disabled (!user.hasPlayer(league.owner))
                            .frame (maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle (leagueIsDeleted ? "" :  league.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
            }
        }
        .onAppear() {
            leagueName = league.name
//            leaguePlayers = league.players
        }
        .onChange(of: editMode!.wrappedValue) { (oldValue, newValue) in
            isEditing = newValue.isEditing
        }
        .onChange(of: isEditing) {
            if isEditing {
                leagueName  = league.name
                leagueUsers = league.users
            }
            else {
                league.name = leagueName

                let usersToDisable = Set(league.users).subtracting(leagueUsers)

                if let share = try? controller.container.fetchShares (matching: [league.objectID]).first?.value {
                    share.participants
                        .forEach { participant in
                            //
                            // For this to work, the User created from the league player needs to
                            // have equivalent to lookupInfo data.  Instead they are all `nil`.
                            //
                            // See User.create(... :player) - there is nothing to copy.  User stores
                            // lookupInfo and passes it to Player, then User.create(:player)  gets
                            // the data.
                            //
                            if usersToDisable.contains (where: { $0.matchesUserInfo (participant.userIdentity.lookupInfo ) }) {
                                share.removeParticipant (participant)
                            }
                        }
                }

                try? context.save()
            }
        }
        .sheet (isPresented: $showCreateGame) {
            GameCreateView (league: league, game: $createdGame) { saved in
                if let _ = createdGame {
                    try? context.save()
                }
                showCreateGame = false
            }
        }
        .sheet (isPresented: $showInvitePlayers) {
            let shares = try! controller.container.fetchShares (matching: [league.objectID])
            let (_, share) = shares.first ?? (nil, {
                var newShare : CKShare? = nil
                controller.container.share([league], to: nil) { objectIDs, share, container, error in
                    guard let share = share
                    else { return }
                    
                    // Configure the share
                    share[CKShare.SystemFieldKey.title] = league.name
                    newShare = share
                }
                return newShare!
            }())

            // There should be at most one 'CKShare' for `League`
            CloudSharingView (presentationMode: _presentationMode,
                              container: controller.cloudKitContainer,
                              object: league,
                              share: share) { (object: NSManagedObject, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) in

                controller.container.share([object], to: share) { objectIDs, share, container, error in
                    // Configure share
                    completion (share, container, error)
                    //showInvitePlayers = false
                }
            }
        }
        .onReceive (NotificationCenter.default.storeDidChangePublisher) { notification in
            processStoreChangeNotification(notification)
        }

    }

    /**
     - The notification isn't relevant to the private database.
     - The notification transaction isn't empty. When a share changes, Core Data triggers a store
     remote change notification with no transaction.
     In that case, grab the share with the same title, and use it to update the UI.
     */
    private func processStoreChangeNotification(_ notification: Notification) {
        // Ignore the notification in the following cases:

        print("\n\nJKP: \(#function): LeagueView: Notification: \(notification.description)")
        
#if false
        // 1) The notification isn't relevant to the private database
        guard let storeUUID = notification.userInfo?[UserInfoKey.storeUUID] as? String,
              storeUUID == controller.storeFor(scope: .private).identifier
        else { return }

        // 2) The notification transaction isn't empty. When a share changes, Core Data triggers a
        //     store remote change notification with no transaction.
        guard let transactions = notification.userInfo?[UserInfoKey.transactions] as? [NSPersistentHistoryTransaction],
              transactions.isEmpty
        else { return }

        if let updatedShare = PersistenceController.shared.share(with: share.title) {
            participants = updatedShare.participants.filter { $0.role != .owner }.map { Participant($0) }

        } else {
            wasShareDeleted = true
        }

#endif
    }
}

extension User {
    func matchesUserInfo (_ info: CKUserIdentity.LookupInfo?) -> Bool {
        guard let info = info else { return false }
        return (recordIdentifier.map { $0 == info.userRecordID?.recordName } ?? false ||
                phoneNumber.map      { $0 == info.phoneNumber  } ?? false ||
                emailAddress.map     { $0 == info.emailAddress } ?? false)
    }
}

#Preview {
    LeagueListView()
        .environment(\.managedObjectContext, PersistenceController.preview.context)
        .environmentObject(User.create(PersistenceController.preview.context,
                                       scope: User.Scope.owner,
                                       name: PersonNameComponents(givenName: "Ed", familyName: "Gamble")))
}

struct LeagueCreateView: View  {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var user: User

    @Binding var league:League?
    func canSave () -> Bool {
        return !leagueName.isEmpty
    }

    var done: ((_ saved:Bool) -> ())

    @State private var leagueName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section ("Configuration") {
                    HStack {
                        Text ("name:")
                            .opacity(0.8)
                            .font (.subheadline)
                        TextField ("required", text: $leagueName)
                            .multilineTextAlignment(TextAlignment.trailing)

                    }
                }

                if let _ = league {
                    Section () {
                        Button ("Delete League", role: .destructive) {
                        }
                        .frame (maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Create League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem (placement: .navigationBarLeading) {
                    Button ("Cancel", role: .cancel) {
                        done (false)
                    }
                }
                ToolbarItem (placement: .navigationBarTrailing) {
                    Button ("Save") {
                        //
                        // Create a `League` with `user` as the owner and the only player.  Other
                        // players will be added as they accept invitations.
                        //
                        let owner = user.createPlayer()

                        league = League.create (context,
                                                name: leagueName,
                                                owner: owner,
                                                players: Set([owner]))
                        user.addLeague(league!)

                        done (true)
                    }
                    .disabled(!canSave())
                }
            }
        }
    }
}

//#Preview {
//    @State var league:League?
//    LeagueCreateView (league: $league) { ignore in
//        return
//    }
//        .environment(\.managedObjectContext, PersistenceController.preview.context)
//}
