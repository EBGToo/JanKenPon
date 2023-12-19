//
//  User.swift
//  JanKenPon
//
//  Created by Ed Gamble on 12/18/23.
//

import CoreData

extension User {
    @nonobjc internal class func fetchRequest (name: String) -> NSFetchRequest<User> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = NSPredicate (format: "moName == %@", name as CVarArg)
        return fetchRequest
    }

    public static func lookupBy (_ context:NSManagedObjectContext, url: URL) -> User? {
        return context.persistentStoreCoordinator!.managedObjectID(forURIRepresentation: url)
            .flatMap { (try? context.existingObject (with: $0)) as? User }
    }

    public static func all (_ context:NSManagedObjectContext) -> Set<User> {
        return Set ((try? context.fetch (User.fetchRequest())) ?? [])
    }
}

extension User {
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

        return Set (moPlayerIDs!.compactMap { url in
            return Player.lookupBy (context, url: url) ?? {
                debugPrint ("User.players: missed URL: \(url.debugDescription)")
                return nil
            }()
        })
    }

    public func addPlayer (_ player: Player) {
        precondition (player.hasUser(self))

        let url = player.objectID.uriRepresentation()
        if !moPlayerIDs!.contains (url) {
            moPlayerIDs!.append(url)
        }
    }

    public func createPlayer (_ context: NSManagedObjectContext? = nil) -> Player {
        let context = context ?? self.managedObjectContext!

        // Create a new player and then save to get the permanent objectId
        let player = Player.create (context, user: self)
        try! context.save()

        // Add `player`
        moPlayerIDs!.append (player.objectID.uriRepresentation())

        return player
    }

    public var leagues: Set<League> {
        guard let context = self.managedObjectContext
        else {
            // User has been deleted
            return Set([])
        }

        return Set (moLeagueIDs!.compactMap { url in
            return League.lookupBy (context, url: url) ?? {
                debugPrint ("User.leagues: missed URL: \(url.debugDescription)")
                return nil
            }()
        })
    }

    public func addLeague (_ league: League) {
        // Confirm, one of `user.players` is in `league.players`

        let url = league.objectID.uriRepresentation()
        if !moLeagueIDs!.contains(url) {
            moLeagueIDs!.append (url)
        }
    }
    
    public static func create (_ context: NSManagedObjectContext,
                               name: PersonNameComponents) -> User {
        let user = User(context: context)

        user.moName = name as NSPersonNameComponents

        user.moLeagueIDs = []
        user.moPlayerIDs = []

        return user
    }
}

class UserBox: ObservableObject {
    @Published var user: User? = nil

    init (_ user: User? = nil) {
        self.user = user
    }
}

