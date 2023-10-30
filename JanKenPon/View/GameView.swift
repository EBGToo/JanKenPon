//
//  GameView.swift
//  JanKenPon
//
//  Created by Ed Gamble on 11/6/23.
//

import SwiftUI

struct GameListView: View {
    @Environment(\.managedObjectContext) private var context

    @Binding var league:League

    @State private var createdGame: Game? = nil
    @State private var showCreateGame = false

    @State private var gamesText: String = ""
    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(league.games)) { game in
                    NavigationLink {
                        GameView (game: game)
                    } label: {
                        Text("\(league.name): Foo")
                    }
                }
                //                .onDelete(perform: deleteItems)
                Section ("Hack") {
                    Text (gamesText)
                }
            }
            .navigationBarTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    Button (action: { showCreateGame = true },
                            label:  { Label("Create Game", systemImage: "plus") })
                }
            }
        }
        .sheet (isPresented: $showCreateGame) {
            GameCreateView(league: $league, game: $createdGame) { saved in
                if let _ = createdGame {
                    try? context.save()
                }
                gamesText = league.games.map { $0.league?.name ?? "<XX>"}.joined(separator: ", ")
                showCreateGame = false
            }
        }
    }
}

struct GameListView_Previews: PreviewProvider {
    struct WithState : View {
        @State private var league: League = League.create (PersistenceController.preview.context,
                                                           name: "Preview One",
                                                           players: Set ([
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Ed", familyName: "Gamble")),
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Naoko", familyName: "Gamble")),
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Kai", familyName: "Gamble")),
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Mitsi", familyName: "Gamble"))
                                                           ]))

        var body: some View {
            GameListView (league: $league)
                .environment(\.managedObjectContext, PersistenceController.preview.context)
        }
    }

    static var previews: some View {
        GameListView_Previews.WithState()
    }
}

// MARK: - Game View

struct GameView: View {
    @Environment(\.managedObjectContext) private var context

    @ObservedObject var game:Game
    @State private var roundIsCompete = false

    var body: some View {
        NavigationStack {
            //let players = Array(game.players)

            Form {
                Section ("Rounds") {

                    Grid {
                        GridRow {
                            ForEach (game.players.sorted(by: Player.byGivenNameSorter))  { player in
                                Text (player.name.givenName!)
                            }
                        }

                        ForEach (game.rounds, id: \.self) { round in
                            GridRow {
                                ForEach (game.players.sorted(by: Player.byGivenNameSorter)) { player in
                                    let move = round.playerMove (player)!

                                    switch move {
                                    case Game.Move.none:
                                        MovePicker(round: round, player: player) {
                                            game.complete(round: round)
                                            try? context.save()
                                        }
                                    default:
                                        Text (Game.Move.done ==  move ? "" : move.name)
                                    }
                                }
                            }
                        }
                    }
                }

                Section ("Winner") {
                    Text (game.winner.map { $0.fullname} ?? "")
                }

                Section ("Players") {
                    ForEach (game.players.sorted(by: Player.byGivenNameSorter)) { player in
                        Text (player.fullname)
                    }
                }

                if nil == game.winner {
                    Section ("Debug") {
                        Text ("Number Of Rounds: \(game.numberOfRounds)")

                        ForEach (game.players.sorted(by: Player.byGivenNameSorter)) { player in
                            Button (player.name.givenName!) {
                                if .none == game.lastRound.playerMove(player)! {
                                    game.lastRound.setPlayerMove(player, Game.Move.randomized())
                                    try! context.save()
                                }
                            }
                            .frame (maxWidth: .infinity)
                            .frame (height: 30)
                        }
                    }
                }
            }
            .navigationBarTitle("Game:Foo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MovePicker: View {
    @Environment(\.managedObjectContext) private var context

    @ObservedObject var round:Round
    @ObservedObject var player:Player
    var onRoundComplete: (() -> Void)? = nil


    let gameMoves = [Game.Move.rock, Game.Move.paper, Game.Move.scissors]

    func bindingForMove (round: Round, player: Player) -> Binding<Game.Move> {
        Binding (
            get: {
                round.playerMove(player)!
            },
            set: { value in
                round.setPlayerMove(player, value);
                try! context.save()
            })
    }

    var body: some View {
        Picker ("Move", selection:bindingForMove (round: round, player: player)) {
            Text ("").tag (Game.Move.none as Game.Move)
            ForEach (gameMoves, id: \.self) { move in
                Text (move.name).tag (move as Game.Move)
            }
        }
        .id ("\(round.index.description):\(player.uuid)")
        .labelsHidden()
        .frame (maxWidth: .infinity)
        .onChange (of: round.isComplete) { old, new in
            if !old && new {
                onRoundComplete? ()
            }
        }
    }
}

struct GameCreateView: View {
    @Environment(\.managedObjectContext) private var context

    @Binding var league:League

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

struct GameCreateView_Previews: PreviewProvider {
    struct WithState : View {
        @State private var game: Game? = nil
        @State private var league: League = League.create (PersistenceController.preview.context,
                                                           name: "Preview One",
                                                           players: Set ([
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Ed", familyName: "Gamble")),
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Naoko", familyName: "Gamble")),
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Kai", familyName: "Gamble")),
                                                            Player.create (PersistenceController.preview.context, name: PersonNameComponents(givenName: "Mitsi", familyName: "Gamble"))
                                                           ]))

        var body: some View {
            GameCreateView (league: $league, game: $game) { (saved:Bool) in return }
                .environment(\.managedObjectContext, PersistenceController.preview.context)
        }
    }

    static var previews: some View {
        GameCreateView_Previews.WithState()
    }
}

//#Preview {
//    @State var game:Game? = nil
//}




