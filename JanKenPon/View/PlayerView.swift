//
//  PlayerView.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import SwiftUI

struct PlayerView: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

#Preview {
    PlayerView()
}


struct PlayerFormFieldsView: View {
    @Binding var playerFamilyName:String
    @Binding var playerGivenName:String

    @Binding var playerLeague:League?
    var leagues:[League]

    var needGhinAndIndex: Bool = true
    var needLeague: Bool = true

    var body: some View {
        SwiftUI.Group {
            HStack {
                Text ("family name:")
                    .opacity(0.8)
                    .font (.subheadline)
                TextField ("required", text: $playerFamilyName)
                    .multilineTextAlignment(TextAlignment.trailing)

            }
            HStack {
                Text ("given name:")
                    .opacity(0.8)
                    .font (.subheadline)
                TextField ("required",  text: $playerGivenName)
                    .multilineTextAlignment(TextAlignment.trailing)

            }

            if needLeague && !leagues.isEmpty {
                Picker (selection: $playerLeague,
                        label: PickerLabel ("league")) {
                    Text("").tag (nil as League?)
                    ForEach (leagues) { league in
                        Text (league.name).tag(league as League?)
                    }
                }
            }
        }
    }
}

struct PickerLabel: View {
    var title:String

    init (_ title: String) {
        self.title = title
    }

    var body: some View {
        Text (title)
            .opacity(0.8)
            .font (.subheadline)
    }
}
