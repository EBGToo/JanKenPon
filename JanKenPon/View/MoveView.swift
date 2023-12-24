//
//  MoveView.swift
//  JanKenPon
//
//  Created by Ed Gamble on 12/24/23.
//

import SwiftUI

struct MoveView: View {
    @EnvironmentObject private var playerForUser: Player
    @ObservedObject var move: Move

    var body: some View {
        let shape = move.shape

        if shape == .none && move.player == playerForUser {
            MovePicker (move: move)
        }
        else {
            ShapeView (shape: shape,
                       completed: move.round.isComplete || move.player == playerForUser)
        }
    }
}

struct MovePicker: View {
    @ObservedObject var move: Move

    let gameShapes = [Move.Shape.rock, Move.Shape.paper, Move.Shape.scissors]

    var body: some View {
        Picker ("Move", selection: $move.shape) {
            ShapeView (shape: Move.Shape.none).tag (Move.Shape.none as Move.Shape)
            ForEach (gameShapes, id: \.self) { shape in
                ShapeView (shape: shape).tag (shape as Move.Shape)
            }
        }
        .id ("\(move.round.index.description):\(move.player.url.description)")
        .labelsHidden()
        .frame (maxWidth: .infinity)
        .frame (height: 75.0)
        .onChange (of: move.moShape) { oldValue, newValue in
            print ("Changed")
        }
        .onChange (of: move.shape) { oldValue, newValue in
            print ("Changed")
        }
        .onChange (of: move) { oldValue, newValue in
            print ("Changed")
        }
//        .onChange (of: move.round.isComplete) { old, new in
//            if !old && new {
//                onRoundComplete? ()
//            }
//        }
    }
}

struct ShapeView: View {
    var shape: Move.Shape
    var completed: Bool = true

    var body: some View {
        if completed {
            switch shape {
            case .none:     return Image (systemName: "questionmark")
            case .done:     return Image (systemName: "checkmark")
            case .rock:     return Image ("shape.rock")
            case .paper:    return Image ("shape.paper")
            case .scissors: return Image ("shape.scissors")
            }
        }
        else {
            return Image (systemName: "dot.circle")
        }
    }
}

