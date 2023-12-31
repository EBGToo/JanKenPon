//
//  User.swift
//  JanKenPon
//
//  Created by Ed Gamble on 12/18/23.
//

import CoreData

extension User {
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

    internal var recordIdentifier: String? {
        return moRecordID
    }

    public var phoneNumber: String? {
        get { return moPhoneNumber }
        set { moPhoneNumber = newValue }
    }

    public var emailAddress: String? {
        get { return moEmailAddress }
        set { moEmailAddress = newValue }
    }

    public var players: Set<Player> {
        guard let context = self.managedObjectContext
        else {
            // User has been deleted
            return Set([])
        }

        let players = moPlayerUUIDs!.compactMap { uuid in
            Player.lookupBy (context, uuid: uuid)
        }

        if players.count != moPlayerUUIDs!.count {
            moPlayerUUIDs!.removeAll { uuid in
                !players.contains { uuid == $0.uuid }
            }
        }

        return Set (players)

//        // If a league is deleted, its players are summarily deleted too.  That can leave one of
//        // our UUIDs without a reference.  Clear them out on access.
//        let uuidToPlayerMap = moPlayerUUIDs!
//            .reduce(into: [UUID:Player]()) { result, uuid in
//                if let player = Player.lookupBy(context, uuid: uuid) {
//                    result[uuid] = player
//                }
//            }
//        if uuidToPlayerMap.count != moPlayerUUIDs!.count {
//            moPlayerUUIDs!.removeAll { nil == uuidToPlayerMap[$0] }
//        }
//
//        return Set (uuidToPlayerMap.values)

//        return Set (moPlayerUUIDs!.compactMap { uuid in
//            return Player.lookupBy (context, uuid: uuid) ?? {
//                debugPrint ("User.players: missed UUID: \(uuid.debugDescription)")
//                return nil
//            }()
//        })
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

        let leagues = moLeagueUUIDs!.compactMap { uuid in
            League.lookupBy (context, uuid: uuid)
        }

        if leagues.count != moLeagueUUIDs!.count {
            moLeagueUUIDs!.removeAll { uuid in
                !leagues.contains { $0.uuid == uuid }
            }
        }

        return Set (leagues)

//        let uuidToLeagueMap = moLeagueUUIDs!
//            .reduce(into: [UUID:League]()) { result, uuid in
//                if let league = League.lookupBy (context, uuid: uuid) {
//                    result[uuid] = league
//                }
//            }
//        if uuidToLeagueMap.count != moLeagueUUIDs!.count {
//            moLeagueUUIDs!.removeAll { nil == uuidToLeagueMap[$0] }
//        }
//
//        return Set (uuidToLeagueMap.values)
        
//        return Set (moLeagueUUIDs!.compactMap { uuid in
//            return League.lookupBy (context, uuid: uuid) ?? {
//                debugPrint ("User.leagues: missed UUID: \(uuid.debugDescription)")
//                return nil
//            }()
//        })
    }

    public func addLeague (_ league: League) {
        // Confirm, one of `user.players` is in `league.players`

        let uuid = league.uuid
        if !moLeagueUUIDs!.contains(uuid) {
            moLeagueUUIDs!.append (uuid)
        }
    }
    
    public func remLeague (_ league: League) {
        if let index = moLeagueUUIDs!.firstIndex (of: league.uuid) {
            moLeagueUUIDs?.remove(at: index)
        }
    }

    public static let nameDefault = PersonNameComponents (
        givenName: "",
        familyName: "Me")

    public static func create (_ context: NSManagedObjectContext,
                               scope: User.Scope,
                               name: PersonNameComponents,
                               phoneNumber: String? = nil,
                               emailAddress: String? = nil,
                               recordID: String? = nil) -> User {
        let user = User(context: context)

        user.moUUID     = UUID()
        user.moRecordID = recordID
        user.moScope    = Int16(scope.rawValue)

        user.moName         = name as NSPersonNameComponents
        user.moPhoneNumber  = phoneNumber
        user.moEmailAddress = emailAddress

        user.moLeagueUUIDs = []
        user.moPlayerUUIDs = []

        return user
    }
}

extension User {
    public enum Scope: Int {
        /// The user owns this App on this device.  The `moRecordID` references the public database
        /// User record for this App
        case owner

        /// The user has the App on another device (hasiCloudAccount).  There is no `moRecordID`
        case user

        /// The user does not have the App but is present in the system.  This makes sense for the
        /// `AG Scoring App` where there will be players in a League/Round for which the `score`
        /// (an Owner on their device; a User on another device) keeps a score.
        case player
    }
}


class UserBox: ObservableObject {
    @Published var user: User? = nil

    init (_ user: User? = nil) {
        self.user = user
    }
}

