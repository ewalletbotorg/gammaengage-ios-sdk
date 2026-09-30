# GammaEngage iOS SDK

Registers a device for GammaEngage mobile push and reports notification opens. Requires iOS 13+.

> **Status: preview.** The signing, request format, token lifecycle and tap handling are unit-tested, but the SDK has not yet been run against a real iPhone with APNs. Verify it in your own app before shipping.

The SDK does not include Firebase. Your app fetches the FCM token with the Firebase iOS SDK and hands it over, so you control the Firebase version and setup.

## What you set up first (Apple and Firebase, required for any iOS push)

1. An Apple Developer account, with the **Push Notifications** capability enabled for your app.
2. Create a Firebase project, register your iOS app, and add `GoogleService-Info.plist` to your app.
3. Upload an **APNs authentication key** to the Firebase project (Project settings → Cloud Messaging).
4. Add the Firebase iOS SDK (`FirebaseMessaging`) to your app.
5. In GammaEngage, upload the Firebase project's **service account JSON** under Settings → Channels → Push for your brand.

## Install

In Xcode: File → Add Package Dependencies, and enter this repository's URL.

## Use

```swift
import GammaEngage
import FirebaseMessaging

// application(_:didFinishLaunchingWithOptions:)
GammaEngage.configure(GammaEngageConfig(
    baseURL: "https://your-gammaengage-host",
    brandId: "your-brand-id",
    apiKey: "your-api-key",
    hmacSecret: "your-hmac-secret"   // optional; signs every request when set
))

// MessagingDelegate — called at every launch and whenever Firebase refreshes the token
func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let fcmToken { GammaEngage.setPushToken(fcmToken) }
}

// After the player logs in
GammaEngage.setPlayer("player-123")

// On logout — stops the previous player's pushes reaching this device
GammaEngage.logout()
```

The token and the player can arrive in either order. The SDK remembers the token until a player is set, then registers it.

### Notification taps

```swift
// UNUserNotificationCenterDelegate
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    GammaEngage.handle(response: response)
    completionHandler()
}
```

## Behaviour to know about

- A failed registration is retried the next time your app passes the token (every launch).
- If unregistering on logout fails (offline), it is retried on the next launch, so a previous player's token is not left behind.
- The HMAC secret ships inside your app, so treat it as identifying the app, not as a private credential.
