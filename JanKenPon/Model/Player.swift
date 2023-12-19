//
//  Player.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import CoreData

extension Player {
    public static func lookupBy (_ context: NSManagedObjectContext, url: URL) -> Player? {
        return context.persistentStoreCoordinator!.managedObjectID( forURIRepresentation: url)
            .flatMap { (try? context.existingObject (with: $0)) as? Player }
    }

    public static func all (_ context:NSManagedObjectContext) -> Set<Player> {
        return Set ((try? context.fetch (Player.fetchRequest())) ?? [])
    }

    public static func allCount (_ context:NSManagedObjectContext) -> Int {
        return (try? context.count (for: Player.fetchRequest())) ?? 0
    }
}

extension Player {
    public var name:PersonNameComponents {
        get { return moName! as PersonNameComponents }
        set { moName = newValue as NSPersonNameComponents }
    }

    public var fullname:String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter.string (from: name)
    }

    ///
    /// Returns this `player's` user; or nil if the user has been deleted.
    ///
    public var user: User? {
        return User.lookupBy (managedObjectContext!, url: moUserID!)
    }

    public func hasUser (_ user: User) -> Bool {
        return moUserID == user.objectID.uriRepresentation()
    }

    public var league:League {
        return moLeague!
    }

    public var games: Set<Game> {
        return moGames! as! Set<Game>
    }

    internal var url: URL {
        return objectID.uriRepresentation()
    }

    public static func create (_ context:NSManagedObjectContext,
                               user: User) -> Player {
        let player = Player (context: context)

        player.moName   = user.name as NSPersonNameComponents
        player.moUserID = user.objectID.uriRepresentation()

        player.moLeague = nil
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

