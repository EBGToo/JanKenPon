//
//  User.swift
//  JanKenPon
//
//  Created by Ed Gamble on 12/18/23.
//

import CoreData

extension User {
    @nonobjc internal class func fetchRequest (name: PersonNameComponents) -> NSFetchRequest<User> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = NSPredicate (format: "moName == %@", name as CVarArg)
        return fetchRequest
    }

    @nonobjc internal class func fetchRequest (recordID: String) -> NSFetchRequest<User> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = NSPredicate (format: "moRecordID == %@", recordID as CVarArg)
        return fetchRequest
    }

    @nonobjc internal class func fetchRequest (uuid: UUID) -> NSFetchRequest<User> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = NSPredicate (format: "moUUID == %@", uuid as CVarArg)
        return fetchRequest
    }

    public static func lookupBy (_ context: NSManagedObjectContext, uuid: UUID) -> User? {
        guard let users = try? context.fetch (User.fetchRequest (uuid: uuid)), users.count > 0
        else { return nil }

        return users[0]
    }

    public static func lookupBy (_ context: NSManagedObjectContext, recordID: String) -> User? {
        guard let users = try? context.fetch (User.fetchRequest (recordID: recordID)), users.count > 0
        else { return nil }

        return users[0]
    }

    public static func all (_ context:NSManagedObjectContext) -> Set<User> {
        return Set ((try? context.fetch (User.fetchRequest())) ?? [])
    }
}

extension User {
    internal var uuid:UUID {
        return moUUID!
    }
    
    public var name:PersonNameComponents {
        get { return moName! as PersonNameComponents }
        set { 
            moName = newValue as NSPersonNameComponents
            // Set all player names.
        }
    }

    public var fullname:String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter.string (from: name)
    }

    public var players: Set<Player> {
        guard let context = self.managedObjectContext
        else {
            // User has been deleted
            return Set([])
        }

        return Set (moPlayerUUIDs!.compactMap { uuid in
            return Player.lookupBy (context, uuid: uuid) ?? {
                debugPrint ("User.players: missed UUID: \(uuid.debugDescription)")
                return nil
            }()
        })
    }

    public func addPlayer (_ player: Player) {
        precondition (player.hasUser(self))

        let uuid = player.uuid
        if !moPlayerUUIDs!.contains (uuid) {
            moPlayerUUIDs!.append(uuid)
        }
    }

    public func hasPlayer (_ player: Player) -> Bool {
        return moPlayerUUIDs!.contains(player.uuid)
    }

    ///
    /// Find self's player that is in `league`
    ///
    /// - Parameter league: the league
    ///
    /// - Returns: the player if found
    ///
    public func playerInLeague (_ league: League) -> Player? {
        let playersInLeague = self.players.filter { league.hasPlayer($0) }

        guard playersInLeague.count <= 1
        else {
            preconditionFailure ("Multiple User players in league")
        }

        return playersInLeague.first
    }

    public func createPlayer (_ context: NSManagedObjectContext? = nil) -> Player {
        let context = context ?? self.managedObjectContext!

        // Create a new player and then save to get the permanent objectId
        let player = Player.create (context, user: self)

        // Add `player`
        moPlayerUUIDs!.append (player.uuid)

        return player
    }

    public var leagues: Set<League> {
        guard let context = self.managedObjectContext
        else {
            // User has been deleted
            return Set([])
        }

        return Set (moLeagueUUIDs!.compactMap { uuid in
            return League.lookupBy (context, uuid: uuid) ?? {
                debugPrint ("User.leagues: missed UUID: \(uuid.debugDescription)")
                return nil
            }()
        })
    }

    public func addLeague (_ league: League) {
        // Confirm, one of `user.players` is in `league.players`

        let uuid = league.uuid
        if !moLeagueUUIDs!.contains(uuid) {
            moLeagueUUIDs!.append (uuid)
        }
    }
    
    public static func create (_ context: NSManagedObjectContext,
                               name: PersonNameComponents,
                               recordID: String? = nil) -> User {
        let user = User(context: context)

        user.moUUID     = UUID()
        user.moRecordID = recordID
        user.moName     = name as NSPersonNameComponents

        user.moLeagueUUIDs = []
        user.moPlayerUUIDs = []

        return user
    }
}

class UserBox: ObservableObject {
    @Published var user: User? = nil

    init (_ user: User? = nil) {
        self.user = user
    }
}

