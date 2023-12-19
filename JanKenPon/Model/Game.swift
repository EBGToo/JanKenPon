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

    internal func playerBy (url: URL) -> Player? {
        return players.first { url == $0.objectID.uriRepresentation() }
    }

    public var league:League {
        return moLeague! as League
    }

    public private(set) var winner:Player? {
        get { return moWinner.flatMap { Player.lookupBy(managedObjectContext!, url: $0) } }
        set (winner) { moWinner = winner.map { $0.objectID.uriRepresentation() } }
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

        // Prior .done players are still .done
        // Compute each player's results versus every other player
        let playerResults = players
            .filter { .done != round.playerMove($0) }
            .reduce (into: Dictionary<Player,[Game.Move.Result]>()) { resultMap, player in
                let playerMove = round.playerMove(player)!

                resultMap[player] = players
                    .filter { .done != round.playerMove($0) && $0 != player }
                    .map    { playerMove.result (with: round.playerMove($0)!) }
            }

        let playerNewMove = playerResults
            .reduce(into: Dictionary<Player,Game.Move>()) { moveMap, entry in
                let (player, results) = entry

                let hasLoss = results.contains (.lose)
                let hasWin  = results.contains (.win)
                //let allWin  = results.allSatisfy { .win == $0 }


                moveMap[player] = (hasLoss && !hasWin
                                   ? Game.Move.done     // Player lost or drew every match => done
                                   : Game.Move.none)    // Player never lost and won or drew -> none (pending)
            }

        // See if there is a winner
        if 1 ==  playerNewMove.values.filter ({ Game.Move.none == $0 }).count {
            winner = playerNewMove
                .first { (player, move) in Game.Move.none == move }
                .map   { (player, move) in player }
        }

        // If there is a winner, done
        guard nil == winner else { return }

        // Another round is needed
        let newRound = Round.create (managedObjectContext!, game: self)

        players.forEach { player in
            newRound.setPlayerMove(player, playerNewMove[player] ?? Move.done)
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

    private func playersIn (round: Round, having result: Game.Move.Result) -> Set<Player> {
        precondition (round.isComplete)

        // Remove .done players
        let players = players.filter { .done != round.playerMove($0)! }

        return players.filter { player in
                let playerMove = round.playerMove(player)!
                precondition (.none != playerMove)

                // Losers must not win any match; that is, must lose or draw every match
                return players.allSatisfy { other in
                    if other == player { return true }

                    let otherMove = round.playerMove(other)!
                    precondition(.none != otherMove)

                    return result == playerMove.result (with: otherMove)
                }
            }
    }

    public func losersIn (round: Round) -> Set<Player> {
        // return playersIn(round: round, having: .lose)
        precondition (round.isComplete)

        // Remove .done players
        let players = players.filter { .done != round.playerMove($0)! }

        return players.filter { player in
            let playerMove = round.playerMove(player)!
            precondition (.none != playerMove)

            // Losers must not win any match; that is, must lose or draw every match
            return players.allSatisfy { other in
                if other == player { return true }

                let otherMove = round.playerMove(other)!
                precondition(.none != otherMove)

                return .win != playerMove.result (with: otherMove)
            }
        }
    }

    public func winnersIn (round: Round) -> Set<Player> {
        precondition (round.isComplete)

        // Remove .done players
        let players = players.filter { .done != round.playerMove($0)! }

        return players.filter { player in
            let playerMove = round.playerMove(player)!
            precondition (.none != playerMove)

            // Losers must not win any match; that is, must lose or draw every match
            return players.allSatisfy { other in
                if other == player { return true }

                let otherMove = round.playerMove(other)!
                precondition(.none != otherMove)

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
    public enum Move : Int, CaseIterable {
        case none
        case rock
        case paper
        case scissors
        case done

        public enum Result {
            case none
            case win
            case draw
            case lose
        }

        public func result (with move: Move) -> Result {
            if .none == move { return .none }
            if self  == move { return .draw }

            switch self {
            case .none:     return .none
            case .rock:     return move == .scissors ? .win : .lose
            case .paper:    return move == .rock     ? .win : .lose
            case .scissors: return move == .paper    ? .win : .lose
            case .done:     return .none
            }
        }

        public var label:String {
            switch self {
            case .none:     return "N"
            case .rock:     return "R"
            case .paper:    return "P"
            case .scissors: return "S"
            case .done:     return "D"
            }
        }

        public var name:String {
            switch self {
            case .none:     return "None"
            case .rock:     return "Rock"
            case .paper:    return "Paper"
            case .scissors: return "Scissors"
            case .done:     return "Done"
            }
        }

        public static func randomized () -> Move {
            return Move (rawValue: Int.random (in: Move.rock.rawValue...Move.scissors.rawValue))!
        }
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
