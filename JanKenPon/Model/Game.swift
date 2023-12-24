//
//  Game.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import CoreData

extension Game {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<Game> {
//        return NSFetchRequest<Game>(entityName: "Game")
//    }

    public static func all (_ context:NSManagedObjectContext) -> Set<Game> {
        let games = (try? context.fetch (Game.fetchRequest())) ?? []
        return Set(games)
    }

    public static func allCount (_ context:NSManagedObjectContext) -> Int {
        return (try? context.count (for: Game.fetchRequest())) ?? 0
    }
}

extension Game {
    public var date:Date {
        return moDate!
    }

    public var players:Set<Player> {
        return moPlayers! as! Set<Player>
    }

    public func hasPlayer (_ player: Player) -> Bool {
        return players.contains (player)
    }

    internal func playerBy (uuid: UUID) -> Player? {
        return players.first { uuid == $0.uuid }
    }

    internal func playersNotDoneIn (round: Round) -> Set<Player> {
        return players.filter { !round.playerMove($0)!.hasShape (.done) }
    }

    public var league:League {
        return moLeague! as League
    }

    public private(set) var winner:Player? {
        get { return moWinnerUUID.flatMap { Player.lookupBy(managedObjectContext!, uuid: $0) } }
        set (winner) { moWinnerUUID = winner.map { $0.uuid } }
    }

    public var rounds: Array<Round> {
        return (moRounds! as! Set<Round>).sorted { $0.index < $1.index }
    }

    public var numberOfRounds: Int {
        return moRounds!.count
    }

    public func round (at index: Int) -> Round {
        precondition(index < numberOfRounds)
        return rounds[index]
    }

    public var lastRound: Round {
        precondition (numberOfRounds >= 1)
        return round (at: numberOfRounds - 1)
    }

    public func complete (round: Round) {
        guard round.isComplete   else { return }
        guard round == lastRound else { return }
        guard nil   == winner    else { return }

        // Only interested in !.done players
        let players = playersNotDoneIn (round: round)

        // Compute each player's results versus every other player
        let playerResults = players
            .reduce (into: Dictionary<Player,[Move.Result]>()) { resultMap, player in
                let playerMove = round.playerMove(player)!

                resultMap[player] = players
                    .filter { $0 != player }
                    .map    { playerMove.result (with: round.playerMove($0)!) }
            }

        let playerNewShape = playerResults
            .reduce (into: Dictionary<Player,Move.Shape>()) { moveMap, entry in
                let (player, results) = entry

                let hasLoss = results.contains (.lose)
                let hasWin  = results.contains (.win)
                //let allWin  = results.allSatisfy { .win == $0 }


                moveMap[player] = (hasLoss && !hasWin
                                   ? Move.Shape.done     // Player lost or drew every match => done
                                   : Move.Shape.none)    // Player never lost and won or drew -> none (pending)
            }

        // See if there is a winner
        if 1 ==  playerNewShape.values.filter ({ .none == $0 }).count {
            winner = playerNewShape
                .first { (player, move) in .none == move }
                .map   { (player, move) in player }
        }

        // If there is a winner, done
        guard nil == winner else { return }

        // Another round is needed
        let newRound = Round.create (managedObjectContext!, game: self)

        self.players.forEach { player in
            newRound.setPlayerShape (player, playerNewShape[player] ?? .done)
        }
    }

//    public func newRound () -> Round {
//        return players.reduce(into: Round()) { result, player in
//            result[player] = Game.Move.none
//        }
//    }
//
//    public func addRound (_ round: Round) {
//        moRounds!.append (round.reduce (into: Dictionary<UUID,Int>()) { moRound, entry  in
//            let (player, move) = entry
//            moRound[player.uuid] = move.rawValue
//        })
//    }
//
//    private func asRound (_ moRound: Dictionary<UUID,Int>) -> Round {
//        return moRound.reduce (into: Round()) { round, entry  in
//            let player = players.first { $0.uuid == entry.key }!
//
//            round[player] = Game.Move (rawValue: entry.value)
//        }
//    }
//
//    public func assignMove (_ move: Move, player: Player) {
//        precondition (numberOfRounds >= 1)
//
//        var moRound = moRounds! [numberOfRounds - 1]
//        moRound[player.uuid] = move.rawValue
//    }
//
//    public func isComplete (round: Round) -> Bool {
//        players.allSatisfy { player in
//            return .none !=  round[player]!
//        }
//    }
//
//    public var isComplete: Bool {
//        let round = lastRound
//
//        // The round itself must be complete
//        guard isComplete(round: round) else
//        { return false }
//
//        return 1 == winnersIn (round: round).count
//    }

    private func playersIn (round: Round, having result: Move.Result) -> Set<Player> {
        precondition (round.isComplete)
        
        // Remove .done players
        let players = players.filter { !round.playerMove($0)!.hasShape (.done) }

        return players.filter { player in
            let playerMove = round.playerMove(player)!
            precondition (!playerMove.hasShape(.none))

            // Losers must not win any match; that is, must lose or draw every match
            return players.allSatisfy { other in
                if other == player { return true }
                
                let otherMove = round.playerMove(other)!
                precondition (!otherMove.hasShape(.none))

                return result == playerMove.result (with: otherMove)
            }
        }
    }

    public func losersIn (round: Round) -> Set<Player> {
        // return playersIn(round: round, having: .lose)
        precondition (round.isComplete)

        // Remove .done players
        let players = players.filter { !round.playerMove($0)!.hasShape(.done) }

        return players.filter { player in
            let playerMove = round.playerMove(player)!
            precondition (!playerMove.hasShape(.none))

            // Losers must not win any match; that is, must lose or draw every match
            return players.allSatisfy { other in
                if other == player { return true }

                let otherMove = round.playerMove(other)!
                precondition (!otherMove.hasShape(.none))

                return .win != playerMove.result (with: otherMove)
            }
        }
    }

    public func winnersIn (round: Round) -> Set<Player> {
        precondition (round.isComplete)

        // Remove .done players
        let players = players.filter { !round.playerMove($0)!.hasShape(.done) }

        return players.filter { player in
            let playerMove = round.playerMove(player)!
            precondition (!playerMove.hasShape(.none))

            // Losers must not win any match; that is, must lose or draw every match
            return players.allSatisfy { other in
                if other == player { return true }

                let otherMove = round.playerMove(other)!
                precondition (!otherMove.hasShape(.none))

                return .win == playerMove.result (with: otherMove)
            }
        }
    }


    public static func create (_ context:NSManagedObjectContext,
                               league: League,
                               date: Date,
                               players: Set<Player>) -> Game {
        let game = Game (context: context)

        game.moLeague = league
        league.addToMoGames (game)

        game.moDate   = date
        game.moRounds = NSSet()

        game.addToMoPlayers (players as NSSet)
        //players.forEach { $0.addToMoGames(game) }

        // Start with one round; all players' move is .none
        let _ = Round.create (context, game: game)

        return game
    }
}

extension Game {
    public static let byDataSorter = { (g1:Game, g2:Game) -> Bool in
        return g1.date < g2.date
    }

}

extension Game {
//    public enum MoveStatus: Hashable {
//        case eliminated         // Player has been eliminted
//        case waiting            // 
//        case completed (Move)
//
//        public func encode () -> Int {
//            switch self {
//            case .eliminated:  return 0
//            case .waiting:     return 1
//            case .completed(let move): return 2 + move.rawValue
//            }
//        }
//
//        public static func decode (_ value: Int) -> MoveStatus? {
//            switch value {
//            case 0:  return .eliminated
//            case 1:  return .waiting
//            default: return Move (rawValue: value - 2).map { .completed($0) }
//            }
//        }
//
//        public func hash (into hasher: inout Hasher) {
//            switch self {
//            case .eliminated:   hasher.combine (0)
//            case .waiting:      hasher.combine (1)
//            case .completed(let move): hasher.combine (2 + move.rawValue)
//            }
//        }
//    }

    // A map from the players in the round to their move, if they have made one


}
