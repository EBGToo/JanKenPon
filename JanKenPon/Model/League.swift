//
//  League.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import CoreData

extension League {

    @nonobjc internal class func fetchRequest (uuid: UUID) -> NSFetchRequest<League> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = NSPredicate (format: "moUUID == %@", uuid as CVarArg)
        return fetchRequest
    }

    public static func lookupBy (_ context: NSManagedObjectContext, uuid: UUID) -> League? {
        guard let leagues = try? context.fetch (League.fetchRequest (uuid: uuid)), leagues.count > 0
        else { return nil }

        return leagues[0]
    }

    public static func all (_ context:NSManagedObjectContext) -> Set<League> {
        let leagues = (try? context.fetch (League.fetchRequest())) ?? []
        return Set(leagues)
    }

    public static func allCount (_ context:NSManagedObjectContext) -> Int {
        return (try? context.count (for: League.fetchRequest())) ?? 0
    }
}

extension League {
    internal var uuid: UUID {
        return moUUID!
    }

    public var name:String {
        get { return moName! }
        set { moName = newValue }
    }

    public var date: Date {
        return moDate!
    }

    public var owner:Player {
        get { return Player.lookupBy (managedObjectContext!, uuid: moOwnerUUID!)! }
        set (owner) { moOwnerUUID = owner.uuid }
    }

    public var players:Set<Player> {
        get { return moPlayers! as! Set<Player> }
        set { moPlayers = (newValue as NSSet) }
    }

    public func addPlayer (_ player: Player) {
        addToMoPlayers (player)
        player.moLeague = self
    }

    public func remPlayer (_ player: Player) {
        removeFromMoPlayers(player)
        player.moLeague = nil
    }

    public func hasPlayer (_ player: Player) -> Bool {
        return players.contains(player)
    }

    public var games:Set<Game> {
        return moGames! as! Set<Game>
    }

    public static func create (_ context:NSManagedObjectContext,
                               name: String,
                               owner: Player,
                               players: Set<Player> = Set()) -> League {
        let league = League (context: context)

        league.moUUID = UUID()
        league.moName = name
        league.moDate = Date.now

        league.owner = owner

        league.addToMoPlayers (players as NSSet)
        players.forEach { $0.moLeague = league }

        league.moGames = NSSet()

        return league
    }

    public static let byDateSorter = { (l1: League, l2: League) -> Bool in
        return l1.date < l2.date
    }
}
