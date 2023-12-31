//
//  GameView.swift
//  JanKenPon
//
//  Created by Ed Gamble on 11/6/23.
//

import SwiftUI

struct GameListView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var playerForUser: Player

    @ObservedObject var league:League

    @State private var createdGame: Game? = nil
    @State private var showCreateGame = false

    @State private var gamesText: String = ""
    var body: some View {
        NavigationStack {
            Form {
                List(Array(league.games)) { game in
                    NavigationLink {
                        GameView (game: game)
                    } label: {
                        Text(LeagueView.dateFormatter.string(from: game.date))
                    }
                }
                //                .onDelete(perform: deleteItems)
            }
            .navigationBarTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
//            .navigationDestination (for: Game.self) { game in
//                GameView (game: game)
//            }
            .toolbar {
                ToolbarItem {
                    Button (action: { showCreateGame = true },
                            label:  { Label("Create Game", systemImage: "plus") })
                }
            }
        }
        .sheet (isPresented: $showCreateGame) {
            GameCreateView(league: league, game: $createdGame) { saved in
                if let _ = createdGame {
                    try? context.save()
                }
                gamesText = league.games.map { $0.league.name }.joined(separator: ", ")
                showCreateGame = false
            }
        }
    }
}

struct GameListView_Previews: PreviewProvider {
    struct WithState : View {
        private static var count: Int = 1
        private static let users = [
            User.create (PersistenceController.preview.context, scope: .owner, name: PersonNameComponents(givenName: "Ed", familyName: "Gamble")),
            User.create (PersistenceController.preview.context, scope: .owner, name: PersonNameComponents(givenName: "Naoko", familyName: "Gamble")),
            User.create (PersistenceController.preview.context, scope: .owner, name: PersonNameComponents(givenName: "Kai", familyName: "Gamble")),
            User.create (PersistenceController.preview.context, scope: .owner, name: PersonNameComponents(givenName: "Mitsi", familyName: "Gamble"))
        ]

//        private var players: [Player]
        @StateObject private var league: League
        private var owner: Player

        init () {
            let context = PersistenceController.preview.context

            let players = GameListView_Previews.WithState.users
                .map { Player.create(context, user: $0) }

            self.owner = players[0]
            self._league = StateObject (wrappedValue: League.create (context,
                                                                     name: "Preview \(GameListView_Previews.WithState.count)",
                                                                     owner: players[0],
                                                                     players: Set (players)))
            GameListView_Previews.WithState.count += 1
        }

        var body: some View {
            GameListView (league: league)
                .environment(\.managedObjectContext, PersistenceController.preview.context)
                .environmentObject(owner)
        }
    }

    static var previews: some View {
        GameListView_Previews.WithState ()
    }
}

// MARK: - Game View

struct GameView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var playerForUser: Player

    @ObservedObject var game:Game
    @State private var moveChanged = false
    @State private var roundIsComplete = false
    @State private var updates = 0

    private func completeRound (_ round: Round, player: Player? = nil ) {
        game.complete (round: round, player: player ?? playerForUser)
        if round.isComplete { updates = 0 }
        else { updates += 1 }
    }

    var body: some View {
        NavigationStack {
            //let players = Array(game.players)

            Form {
                let players = game.players.sorted (by: Player.byGivenNameSorter)
                Section ("Rounds") {
                    Grid {
                        GridRow {
                            ForEach (players)  { player in
                                Text (player.name.givenName!)
                            }
                        }

                        ForEach (game.rounds, id: \.self) { round in
                            GridRow {
                                ForEach (players) { player in
                                    if let move = round.playerMove (player) {
                                        MoveView (move: move, changed: $moveChanged)
                                            // This is required for subsequent onChange() to fire??
                                            .onChange(of: moveChanged) { oldChange, newChange in
                                                if !oldChange && newChange { moveChanged = false }
                                            }
                                            // This is ONLY called if the above `onChange` exists??
                                            .onChange (of: move.shape) { oldShape, newShape in
                                                if move.round.isComplete {
                                                    completeRound (move.round)
//                                                    game.complete (round: move.round, player: playerForUser)
                                                }
                                                try? context.save()
                                            }
                                    }
                                    else {
                                        Text ("Error: No move for player: \(player.fullname)")
                                    }
                                }
                                //                                    .frame (width: width, height: 30)
                            }
                            //.frame (height: 30)
                        }
                    }
                }

                Section ("Winner") {
                    Text (game.winner.map { $0.fullname} ?? "")
                }

                Section ("Owner") {
                    Text (game.players.first?.fullname ?? "")
                }

                Section ("Players") {
                    ForEach (players) { player in
                        Text (player.fullname)
                    }
                }

                if nil == game.winner {
                    Section ("Debug") {
                        Text ("Number Of Rounds: \(game.numberOfRounds):\(updates)")

                        ForEach (players) { player in
                            Button (player.name.givenName!) {
                                game.lastRound.setPlayerShape (player, Move.Shape.randomized())
                                completeRound (game.lastRound, player: player)
                                try! context.save()
                            }
                            .disabled(.none != game.lastRound.playerShape(player)! || playerForUser == player)
                            .frame (maxWidth: .infinity)
                            .frame (height: 30)
                        }
                    }
                }
            }
            .navigationBarTitle(LeagueView.dateFormatter.string(from: game.date))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GameCreateView: View {
    @Environment(\.managedObjectContext) private var context

    @ObservedObject var league:League
    @Binding var game:Game?

    var done: ((_ saved:Bool) -> ())

    func canSave () -> Bool {
        return true
    }

    @State private var players: Set<Player> = Set()
    
    func bindingFor (player: Player) -> Binding<Bool> {
        return Binding(
            get: { players.contains(player) },
            set: { (on) in
                if on { players.insert(player) }
                else  { players.remove(player) }
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text ("league:")
                    Spacer()
                    Text (league.name)
                }

                Section ("Players") {
                    ForEach (Array(league.players)) { player in
                        Toggle (player.fullname, isOn: bindingFor(player: player))
                    }
                }
            }
            .navigationTitle ("Create Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem (placement: .navigationBarLeading) {
                    Button ("Cancel", role: .cancel) {
                        done (false)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button ("Save") {
                        game = Game.create (context, league: league, date: Date.now, players: players)
                        done (true)
                    }
                    .disabled(!canSave())
                }
            }
        }
    }
}

//struct GameCreateView_Previews: PreviewProvider {
//    struct WithState : View {
//        @State private var game: Game? = nil
//        @StateObject private var league: League = League.create (PersistenceController.preview.context,
//                                                                  name: "Preview One",
//                                                                  players: Set ([
//                                                                    Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Ed", familyName: "Gamble")),
//                                                                    Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Naoko", familyName: "Gamble")),
//                                                                    Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Kai", familyName: "Gamble")),
//                                                                    Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Mitsi", familyName: "Gamble"))
//                                                                  ]))
//
//        var body: some View {
//            GameCreateView (league: league, game: $game) { (saved:Bool) in return }
//                .environment(\.managedObjectContext, PersistenceController.preview.context)
//        }
//    }
//
//    static var previews: some View {
//        GameCreateView_Previews.WithState()
//    }
//}
