# SkipNotify

A [Skip](https://skip.dev) framework for cross-platform push notifications
on iOS and Android **without** depending on the `com.google.firebase:firebase-messaging` library.

- **iOS**: Uses the native `UserNotifications` framework and APNs.
- **Android**: Interfaces directly with Google Mobile Services (GMS) via the
  C2DM registration intent to obtain FCM tokens, requiring only that GMS
  (Google Play Services) is present on the device.

## Setup

To include this framework in your project, add the following
dependency to your `Package.swift` file:

```swift
let package = Package(
    name: "my-package",
    products: [
        .library(name: "MyProduct", targets: ["MyTarget"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.dev/skip-notify.git", "0.0.0"..<"2.0.0"),
    ],
    targets: [
        .target(name: "MyTarget", dependencies: [
            .product(name: "SkipNotify", package: "skip-notify")
        ])
    ]
)
```

## Usage

### Fetching a Push Notification Token

```swift
import SkipNotify

do {
    let token = try await SkipNotify.shared.fetchNotificationToken()
    print("Push token: \(token)")
} catch {
    print("Failed to get push token: \(error)")
}
```

On iOS, this registers with APNs and returns the device token as a hex string.
On Android, this sends a C2DM registration intent to GMS and returns
the FCM registration token.

### Checking GMS Availability

Before requesting a token on Android, you can check whether Google Mobile
Services is available on the device:

```swift
if SkipNotify.shared.isGMSAvailable {
    let token = try await SkipNotify.shared.fetchNotificationToken()
} else {
    print("GMS not available: \(SkipNotify.shared.gmsStatusDescription)")
}
```

| Property | iOS | Android (with GMS) | Android (without GMS) |
|---|---|---|---|
| `isGMSAvailable` | `false` | `true` | `false` |
| `gmsStatusDescription` | `"GMS not applicable (iOS)"` | `"GMS available"` | `"GMS not available"` |

### Sender ID

If your Firebase project requires a specific sender ID (GCM project number),
pass it when fetching the token:

```swift
let token = try await SkipNotify.shared.fetchNotificationToken(senderID: "123456789")
```

## How It Works

### iOS

Standard APNs flow using `UIApplication.shared.registerForRemoteNotifications()`.
The token is received via `NotificationCenter` observers for
`didRegisterForRemoteNotificationsWithDeviceToken` and
`didFailToRegisterForRemoteNotificationsWithError`.

### Android

Instead of depending on `com.google.firebase:firebase-messaging`,
SkipNotify interfaces directly with Google Mobile Services via the
`com.google.android.c2dm.intent.REGISTER` intent:

1. Checks GMS availability by resolving the C2DM registration service
2. Sends a registration `Intent` to `com.google.android.gms` with a
   `Messenger` callback
3. GMS responds asynchronously with a `Message` containing the
   `registration_id` (FCM token)

This approach:
- Eliminates the `firebase-messaging` transitive dependency tree
- Works on any device with Google Play Services installed
- Produces the same FCM token that `FirebaseMessaging.getInstance().token` would return
- Does **not** require Firebase configuration files (`google-services.json`)
  for token retrieval alone

## Configuration

### iOS

Follow the steps described in the
[Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
documentation:

- Select your app from the App Store Connect [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/) page and select "Capabilities" and turn on Push Notifications then click "Save"
- Use the [Push Notifications Console](https://developer.apple.com/notifications/push-notifications-console/) to send a test message to your app.

### Android

No additional Gradle dependencies or `google-services.json` file is required
for token retrieval. GMS (Google Play Services) must be present on the device.

To receive push messages, your app will need to register a `BroadcastReceiver`
for the `com.google.android.c2dm.intent.RECEIVE` action in `AndroidManifest.xml`:

```xml
<receiver android:name=".PushMessageReceiver"
    android:permission="com.google.android.c2dm.permission.SEND"
    android:exported="true">
    <intent-filter>
        <action android:name="com.google.android.c2dm.intent.RECEIVE" />
    </intent-filter>
</receiver>
```

## License

This software is licensed under the 
[Mozilla Public License 2.0](https://www.mozilla.org/MPL/).
