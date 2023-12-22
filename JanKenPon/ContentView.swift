//
//  ContentView.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import SwiftUI
import CoreData

struct ContentView: View {

    var body: some View {
        LeagueListView()
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.shared.context)
}
