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

    public func playerMove (_ player: Player) -> Game.Move? {
        return moPlayerToMoveMap![player.objectID.uriRepresentation()].flatMap { Game.Move(rawValue: $0) }
    }

    public func setPlayerMove (_ player: Player, _ move: Game.Move) {
        precondition(game.hasPlayer(player))

        moPlayerToMoveMap![player.objectID.uriRepresentation()] = move.rawValue
    }

    private var playerMoves: Dictionary<Player,Game.Move> {
        return moPlayerToMoveMap!.reduce(into: Dictionary<Player,Game.Move>()) { result, entry in
            let (playerID, moveValue) = entry

            if let player = game.playerBy (url: playerID),
               let move   = Game.Move (rawValue: moveValue) {
                result[player] = move
            }
        }
    }

    public var isComplete: Bool {
        return playerMoves.values.allSatisfy { .none != $0 }
    }

    public static func create (_ context: NSManagedObjectContext,
                               game: Game) -> Round {
        let round = Round (context: context)

        round.moGame = game
        game.addToMoRounds(round)

        round.moIndex = Int16 (game.numberOfRounds)
        round.moPlayerToMoveMap = game.players.reduce (into: Dictionary<URL, Int>()) { result, player in
            result[player.objectID.uriRepresentation()] = Game.Move.none.rawValue
        }

        return round
    }
}
