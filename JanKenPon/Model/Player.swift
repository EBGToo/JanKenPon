//
//  Player.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import CoreData

extension Player {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<Player> {
//        return NSFetchRequest<Player>(entityName: "Player")
//    }


    public static func all (_ context:NSManagedObjectContext) -> Set<Player> {
        let players = (try? context.fetch (Player.fetchRequest())) ?? []
        return Set(players)
    }

    public static func allCount (_ context:NSManagedObjectContext) -> Int {
        return (try? context.count (for: Player.fetchRequest())) ?? 0
    }

    public static func lookupBy (_ context:NSManagedObjectContext, uuid: UUID) -> Player? {
        Player.all (context)
            .first { $0.uuid == uuid }
    }
}

extension Player {
    public var uuid: UUID {
        return moUUID!
    }
    
    public var name:PersonNameComponents {
        return moName! as PersonNameComponents
    }

    public var fullname:String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter.string(from: name)
    }

    public var leagues:Set<League> {
        return moLeagues! as! Set<League>
    }

    public var isInLeague: Bool {
        return !leagues.isEmpty
    }

    public var games: Set<Game> {
        return moGames! as! Set<Game>
    }

    public static func create (_ context:NSManagedObjectContext,
                               name: PersonNameComponents) -> Player {
        let player = Player (context: context)

        player.moUUID = UUID()
        player.moName = name as NSPersonNameComponents

        player.moLeagues = NSSet()
        player.moGames  = NSSet()

        return player
    }

    public static let byGivenNameSorter = { (p1:Player, p2:Player) -> Bool in
        return (p1.name.givenName!, p1.name.familyName!) < (p2.name.givenName!, p2.name.familyName!)
    }
}

class PlayerBox: ObservableObject {
    @Published var player: Player? = nil

    init (_ player: Player? = nil) {
        self.player = player
    }
}

