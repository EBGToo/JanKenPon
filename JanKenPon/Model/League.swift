//
//  League.swift
//  JanKenPon
//
//  Created by Ed Gamble on 10/30/23.
//

import CoreData

extension League {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<League> {
//        return NSFetchRequest<League>(entityName: "League")
//    }


    public static func all (_ context:NSManagedObjectContext) -> Set<League> {
        let leagues = (try? context.fetch (League.fetchRequest())) ?? []
        return Set(leagues)
    }

    public static func allCount (_ context:NSManagedObjectContext) -> Int {
        return (try? context.count (for: League.fetchRequest())) ?? 0
    }
}

extension League {
    @objc public var name:String {
        get { return moName! }
        set { moName = newValue }
    }

    public var date: Date {
        return moDate!
    }

    public var owner:Player {
        get { return Player.lookupBy (PersistenceController.shared.context, uuid: moOwnerUUID!)! }
        set { moOwnerUUID = newValue.uuid }
    }

    public var players:Set<Player> {
        get { return moPlayers! as! Set<Player> }
        set { moPlayers = (newValue as NSSet) }
    }

    public func addPlayer (_ player: Player) {
        addToMoPlayers (player)
    }

    public func remPlayer (_ player: Player) {
        removeFromMoPlayers(player)
    }

    public var games:Set<Game> {
        return moGames! as! Set<Game>
    }


    public static func create (_ context:NSManagedObjectContext,
                               name: String,
                               players: Set<Player> = Set()) -> League {
        let league = League (context: context)

        league.moName = name
        league.moDate = Date.now
        league.addToMoPlayers (players as NSSet)

        league.moGames = NSSet()

        return league
    }

    public static let byDateSorter = { (l1: League, l2: League) -> Bool in
        return l1.date < l2.date
    }
}
