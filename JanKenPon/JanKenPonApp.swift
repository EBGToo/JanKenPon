//
//  JanKenPonApp.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import SwiftUI

@main
struct JanKenPonApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
