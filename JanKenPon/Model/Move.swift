//
//  Move.swift
//  JanKenPon
//
//  Created by Ed Gamble on 12/23/23.
//

import CoreData

extension Move {
    public var shape: Shape {
        get { Shape (rawValue: Int(moShape))! }
        set { moShape = Int16 (newValue.rawValue) }
    }

    public func hasShape (_ shape: Shape) -> Bool {
        return self.shape == shape
    }

    public func result (with move: Move) -> Result {
        return shape.result (with: move.shape)
    }

    public var player: Player {
        return moPlayer!
    }

    public func hasPlayer (_ player: Player) -> Bool {
        return self.player == player
    }

    public var round: Round {
        return moRound!
    }

    public func hasRound (_ round: Round) -> Bool {
        return self.round == round
    }

    public static func create (_ context:NSManagedObjectContext,
                               round: Round,
                               player: Player,
                               shape: Move.Shape = .none) -> Move {
        let move = Move (context: context)

        move.moShape  = Int16 (shape.rawValue)
        move.moPlayer = player
        move.moRound  = round

        return move
    }
}

extension Move {
    public enum Result {
        case none
        case win
        case draw
        case lose
    }

    public enum Shape : Int, CaseIterable {
        case none
        case rock
        case paper
        case scissors
        case done

        fileprivate func result (with shape: Shape) -> Result {
            if .none == shape { return .none }
            if self  == shape { return .draw }

            switch self {
            case .none:     return .none
            case .rock:     return shape == .scissors ? .win : .lose
            case .paper:    return shape == .rock     ? .win : .lose
            case .scissors: return shape == .paper    ? .win : .lose
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

        public static func randomized () -> Shape {
            return Shape (rawValue: Int.random (in: Shape.rock.rawValue...Shape.scissors.rawValue))!
        }
    }
}
