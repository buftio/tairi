import Foundation

@MainActor
final class GhosttySessionRegistry {
    private(set) var sessionsByID: [UUID: GhosttySession] = [:]
    private(set) var tileToSessionID: [UUID: UUID] = [:]

    var allSessions: [GhosttySession] {
        Array(sessionsByID.values)
    }

    func insert(_ session: GhosttySession) {
        sessionsByID[session.id] = session
    }

    func session(id: UUID) -> GhosttySession? {
        sessionsByID[id]
    }

    func session(forTileID tileID: UUID) -> GhosttySession? {
        guard let sessionID = tileToSessionID[tileID] else { return nil }
        return sessionsByID[sessionID]
    }

    func sessionID(forTileID tileID: UUID) -> UUID? {
        tileToSessionID[tileID]
    }

    func setSessionID(_ sessionID: UUID, forTileID tileID: UUID) {
        tileToSessionID[tileID] = sessionID
    }

    func clearTile(_ tileID: UUID) {
        tileToSessionID.removeValue(forKey: tileID)
    }

    func removeSession(id: UUID) -> GhosttySession? {
        sessionsByID.removeValue(forKey: id)
    }

    func removeTileMappings(forSessionID sessionID: UUID) -> [UUID] {
        let tileIDs = tileToSessionID.compactMap { tileID, mappedSessionID in
            mappedSessionID == sessionID ? tileID : nil
        }
        for tileID in tileIDs {
            tileToSessionID.removeValue(forKey: tileID)
        }
        return tileIDs
    }
}
