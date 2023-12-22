//
//  Player.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import CoreData

extension Player {
    @nonobjc internal class func fetchRequest (uuid: UUID) -> NSFetchRequest<Player> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = NSPredicate (format: "moUUID == %@", uuid as CVarArg)
        return fetchRequest
    }

    public static func lookupBy (_ context: NSManagedObjectContext, uuid: UUID) -> Player? {
        guard let players = try? context.fetch (Player.fetchRequest (uuid: uuid)), players.count > 0
        else { return nil }

        return players[0]
    }

    public static func all (_ context:NSManagedObjectContext) -> Set<Player> {
        return Set ((try? context.fetch (Player.fetchRequest())) ?? [])
    }

    public static func allCount (_ context:NSManagedObjectContext) -> Int {
        return (try? context.count (for: Player.fetchRequest())) ?? 0
    }
}

extension Player {
    internal var uuid: UUID {
        return moUUID!
    }

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
        return User.lookupBy (managedObjectContext!, uuid: moUserUUID!)
    }

    public func hasUser (_ user: User) -> Bool {
        return moUserUUID! == user.uuid
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

        player.moUUID     = UUID()
        player.moName     = user.name as NSPersonNameComponents
        player.moUserUUID = user.uuid

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

