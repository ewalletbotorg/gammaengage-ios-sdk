import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// GammaEngage mobile push SDK.
///
/// ```swift
/// // application(_:didFinishLaunchingWithOptions:)
/// GammaEngage.configure(GammaEngageConfig(baseURL: "...", brandId: "...", apiKey: "...", hmacSecret: "..."))
///
/// // Firebase: messaging(_:didReceiveRegistrationToken:)
/// GammaEngage.setPushToken(fcmToken)
///
/// // after the player logs in
/// GammaEngage.setPlayer("player-123")
///
/// // on logout
/// GammaEngage.logout()
/// ```
public enum GammaEngage {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var core: GammaEngageCore?
    }

    private static let state = State()

    /// Call once at launch. Repeat calls are ignored.
    public static func configure(_ config: GammaEngageConfig) {
        state.lock.lock()
        defer { state.lock.unlock() }
        guard state.core == nil else { return }
        let defaults = UserDefaults(suiteName: "gammaengage_sdk") ?? .standard
        state.core = GammaEngageCore(config: config, defaults: defaults)
    }

    /// Ties this device to a player and registers its push token. Call after login.
    public static func setPlayer(_ playerId: String) {
        current()?.setPlayer(playerId)
    }

    /// Pass the current FCM token here at every launch and whenever Firebase refreshes it.
    public static func setPushToken(_ token: String) {
        current()?.setPushToken(token)
    }

    /// Unregisters this device from the current player so the next user doesn't receive their pushes.
    public static func logout() {
        current()?.logout()
    }

    /// Reports a notification tap if the payload carries a GammaEngage tracking id.
    public static func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        current()?.handle(userInfo: userInfo)
    }

    #if canImport(UserNotifications)
    /// Call from `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    public static func handle(response: UNNotificationResponse) {
        handleNotificationUserInfo(response.notification.request.content.userInfo)
    }
    #endif

    private static func current() -> GammaEngageCore? {
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.core == nil { print("[GammaEngage] configure() must be called first") }
        return state.core
    }
}
