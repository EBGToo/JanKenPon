//
//  Round.swift
//  JanKenPon
//
//  Created by Ed Gamble on 11/10/23.
//

import CoreData

extension Round {

}

extension Round {
    public var index:Int {
        return Int(moIndex)
    }

    public var game: Game {
        return moGame! as Game
    }

    public var moves: Set<Move> {
        return moMoves! as! Set<Move>
    }

    public func playerShape (_ player: Player) -> Move.Shape? {
        return playerMove (player).map(\.shape)
    }

    public func setPlayerShape (_ player: Player, _ shape: Move.Shape) {
        guard let move = playerMove (player)
        else {
            preconditionFailure("Missed player in Round moves")
        }

        move.shape = shape
    }

    internal func playerMove (_ player: Player) -> Move? {
        return moves.first { $0.hasPlayer (player) }
    }

//    private var playerMoves: Dictionary<Player,Move> {
//        return game.players.reduce(into: [Player:Move]()) { result, player in
//            if let move = playerMove (player) {
//                result[player] = move
//            }
//        }
//    }

    public var isComplete: Bool {
        return moves.allSatisfy { !$0.hasShape (Move.Shape.none) }
    }

    public static func create (_ context: NSManagedObjectContext,
                               game: Game) -> Round {
        let round = Round (context: context)

        round.moIndex = Int16 (game.numberOfRounds)

        round.moGame  = game
        game.addToMoRounds(round)

        round.moMoves = Set (game.players.map { Move.create (context, round: round, player: $0) }) as NSSet

        return round
    }
}
