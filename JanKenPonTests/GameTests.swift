//
//  GameTests.swift
//  JanKenPonTests
//
//  Created by Ed Gamble on 11/9/23.
//

import XCTest
@testable import JanKenPon

final class GameTests: XCTestCase {

    var context: NSManagedObjectContext

    var user: Player
    var players: Set<Player>
    var league: League


    override func setUpWithError() throws {
        context = PersistenceController.preview.context

        user = Player.create(context, name: PersonNameComponents (givenName: "Ed", familyName: "Gamble"))

        players = Set ([
            user,
            Player.create (PersistenceController.preview.context, name: PersonNameComponents (givenName: "Naoko", familyName: "Gamble")),
            Player.create (PersistenceController.preview.context, name: PersonNameComponents (givenName: "Kai", familyName: "Gamble")),
            Player.create (PersistenceController.preview.context, name: PersonNameComponents (givenName: "Mitsi", familyName: "Gamble"))
        ])


        league = League.create (PersistenceController.preview.context,
                                name: "Preview One",
                                players: players)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }


    func testRounds() throws {
    }
}
