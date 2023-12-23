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
    @EnvironmentObject private var user: User

//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath: \League.moName, ascending: true)],
//        animation: .default)
//    private var leagues: FetchedResults<League>

    @State var showCreateLeague: Bool = false
    @State private var createdLeague: League? = nil


    var body: some View {
        NavigationStack {
            Text ("Foo")
            List {
                ForEach(user.leagues.sorted(by: League.byDateSorter)) { league in
                    NavigationLink {
                        LeagueView (league: league)
                    } label: {
                        HStack {
                            Text(league.name)
                            Spacer()
                            Text ("(\(league.owner.fullname))")
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
                let (ids, share, container) = try await PersistenceController.shared.container.share([league], to: nil)

                // Configure the share
                share[CKShare.SystemFieldKey.title] = league.name

//                // Share has participant + owner
//                let owner = share.owner
//                // ?? Create a different player for each League ??
//                let ownerAsPlayer = Player.create(context, name: owner.userIdentity.nameComponents!)

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


    @EnvironmentObject private var controller: PersistenceController
    @EnvironmentObject private var user: User

    public static let dateFormatter: DateFormatter = {
        let formatter:DateFormatter = DateFormatter()
        formatter.dateFormat = "E, d MMM yyyy"
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

    var body: some View {
        NavigationStack {
            Form {
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
                    List (league.games.sorted(by: Game.byDataSorter)) { game in
                        NavigationLink {
                            GameView (game: game)
                                .environmentObject(user.playerInLeague(league)!)
                        } label: {
                            Text (LeagueView.dateFormatter.string(from: game.date))
                        }
                    }
                }

                Section ("Owner") {
                    Text (league.owner.fullname)
                        .foregroundStyle (isEditing ? .gray : (colorScheme == .dark ? .white :  .black))
                }

                Section ("Players") {
                    //ScrollView {
                    if isEditing {
                        List (users) { user in
                            Toggle ("U: \(user.fullname)", isOn: bindingFor(user: user))
                                .disabled(self.user == user)

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
#if false
                    Section ("New Player") {
                        HStack {
                            Text ("family name:")
                                .opacity(0.8)
                                .font (.subheadline)
                            TextField ("required", text: $userFamilyName)
                                .multilineTextAlignment(TextAlignment.trailing)

                        }
                        HStack {
                            Text ("given name:")
                                .opacity(0.8)
                                .font (.subheadline)
                            TextField ("required",  text: $userGivenName)
                                .multilineTextAlignment(TextAlignment.trailing)

                        }
                        Button ("Create") {
                            let player = Player.create (context, name: PersonNameComponents (givenName: userGivenName,
                                                                                             familyName: userFamilyName))
                            leagueUsers.insert(player)

                            try? context.save()
                            userGivenName = ""
                            userFamilyName = ""
                        }
                        .frame (maxWidth: .infinity)
                        .disabled(!canCreateUser())
                    }
#endif
                    Section () {
                        Button ("Delete League", role: .destructive) {
                        }
                        .frame (maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle (league.name)
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
                leagueName = league.name
                leagueUsers = Set ((users.startIndex..<users.endIndex)
                    .map { users[$0] }
                    .compactMap { nil == $0.playerInLeague (league) ? nil : $0 })
            }
            else {
                league.name = leagueName
//                league.players = leaguePlayers
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
        .onReceive(NotificationCenter.default.storeDidChangePublisher) { notification in
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

#Preview {
    LeagueListView()
        .environment(\.managedObjectContext, PersistenceController.preview.context)
        .environmentObject(User.create(PersistenceController.preview.context,
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

    @State private var userFamilyName: String = ""
    @State private var userGivenName: String = ""

    func canCreateUser () -> Bool {
        return !userGivenName.isEmpty && !userFamilyName.isEmpty
    }

    @State private var leagueUsers: Set<User> = Set()

    func bindingFor (user: User) -> Binding<Bool> {
        return Binding(
            get: { leagueUsers.contains(user) },
            set: { (on) in
                if on { leagueUsers.insert(user) }
                else  { leagueUsers.remove(user) }
            })
    }

    @FetchRequest(
        sortDescriptors: [], // [NSSortDescriptor(keyPath: \Player.fullname, ascending: true)],
        animation: .default)
    private var users: FetchedResults<User>

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

                Section ("Players") {
                    List (users) { user in
                        Toggle ("U: \(user.fullname)", isOn: bindingFor(user: user))
                    }
                }

                #if false
                Section ("New Player") {
                    HStack {
                        Text ("family name:")
                            .opacity(0.8)
                            .font (.subheadline)
                        TextField ("required", text: $userFamilyName)
                            .multilineTextAlignment(TextAlignment.trailing)

                    }
                    HStack {
                        Text ("given name:")
                            .opacity(0.8)
                            .font (.subheadline)
                        TextField ("required",  text: $userGivenName)
                            .multilineTextAlignment(TextAlignment.trailing)

                    }
                    Button ("Create") {
                         let user = User.create (context, name: PersonNameComponents (givenName: userGivenName,
                                                                                     familyName: userFamilyName))
                        leagueUsers.insert(user)
                        try? context.save()

                        userGivenName = ""
                        userFamilyName = ""
                    }
                    .frame (maxWidth: .infinity)
                    .disabled(!canCreateUser())
                }
                #endif

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
                        // Always add `user`
                        leagueUsers.insert(user)

                        // `user` is the owner
                        let owner = user.createPlayer()

                        let players = leagueUsers
                            .filter { $0 != user}
                            .map    { $0.createPlayer() } + [owner]

                        league = League.create (context,
                                                name: leagueName,
                                                owner: owner,
                                                players: Set(players))
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
