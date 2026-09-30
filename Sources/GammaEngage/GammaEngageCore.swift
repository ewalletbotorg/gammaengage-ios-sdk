import Foundation

final class GammaEngageCore: @unchecked Sendable {
    private enum Key {
        static let player = "player_id"
        static let latestToken = "latest_token"
        static let registeredToken = "registered_token"
        static let pendingRemovalPlayer = "pending_removal_player"
        static let pendingRemovalToken = "pending_removal_token"
    }

    private let defaults: UserDefaults
    private let api: ApiClient
    private let lock = NSLock()
    private var inFlightToken: String?
    private var reportedOpens = Set<String>()

    init(config: GammaEngageConfig, defaults: UserDefaults, transport: Transport = URLSessionTransport()) {
        self.defaults = defaults
        self.api = ApiClient(config: config, transport: transport)
        flushPendingRemoval()
    }

    /// Ties this device to a player. Switching to a different player unregisters the device from the previous one.
    func setPlayer(_ playerId: String) {
        if let previous = defaults.string(forKey: Key.player), previous != playerId {
            logout()
        }
        defaults.set(playerId, forKey: Key.player)
        if let token = defaults.string(forKey: Key.latestToken) {
            register(token)
        }
    }

    /// The app passes the current FCM token here, at every launch and whenever it refreshes.
    /// It's remembered even before a player is set, then registered as soon as there is one.
    func setPushToken(_ token: String) {
        defaults.set(token, forKey: Key.latestToken)
        register(token)
    }

    func logout() {
        guard let player = defaults.string(forKey: Key.player) else { return }
        let token = defaults.string(forKey: Key.registeredToken)
        defaults.removeObject(forKey: Key.player)
        defaults.removeObject(forKey: Key.registeredToken)
        guard let token else { return }
        defaults.set(player, forKey: Key.pendingRemovalPlayer)
        defaults.set(token, forKey: Key.pendingRemovalToken)
        removeToken(player: player, token: token) { [weak self] ok in
            if ok { self?.clearPendingRemoval() }
        }
    }

    func handle(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["tracking_event_id"] as? String, !id.isEmpty else { return }
        lock.lock()
        let isNew = reportedOpens.insert(id).inserted
        lock.unlock()
        if isNew { api.reportOpen(trackingEventId: id) }
    }

    private func register(_ token: String) {
        guard let player = defaults.string(forKey: Key.player) else { return }
        lock.lock()
        if inFlightToken == token {
            lock.unlock()
            return
        }
        inFlightToken = token
        lock.unlock()

        if let previous = defaults.string(forKey: Key.registeredToken), previous != token {
            removeToken(player: player, token: previous, completion: nil)
        }
        api.sendEvent(
            type: "push_token_registered",
            playerId: player,
            payload: [("device_token", token), ("platform", "ios")]
        ) { [weak self] ok in
            guard let self else { return }
            self.lock.lock()
            if self.inFlightToken == token { self.inFlightToken = nil }
            self.lock.unlock()
            if ok { self.defaults.set(token, forKey: Key.registeredToken) }
        }
    }

    private func removeToken(player: String, token: String, completion: (@Sendable (Bool) -> Void)?) {
        api.sendEvent(
            type: "push_token_removed",
            playerId: player,
            payload: [("device_token", token)],
            completion: completion
        )
    }

    private func flushPendingRemoval() {
        guard
            let player = defaults.string(forKey: Key.pendingRemovalPlayer),
            let token = defaults.string(forKey: Key.pendingRemovalToken)
        else { return }
        removeToken(player: player, token: token) { [weak self] ok in
            if ok { self?.clearPendingRemoval() }
        }
    }

    private func clearPendingRemoval() {
        defaults.removeObject(forKey: Key.pendingRemovalPlayer)
        defaults.removeObject(forKey: Key.pendingRemovalToken)
    }
}
