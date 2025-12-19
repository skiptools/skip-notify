# SkipNotify



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
        .package(url: "https://source.skip.tools/skip-notify.git", "0.0.0"..<"2.0.0"),
    ],
    targets: [
        .target(name: "MyTarget", dependencies: [
            .product(name: "SkipNotify", package: "skip-notify")
        ])
    ]
)
```

## Configuration

Enabling push notifications in your app requires a series of steps that differ
between iOS and Android. Following is an outline of the tasks required to
activate and configure push notifications.

### iOS

Follow the steps described in the 
[Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
documentation:

- Select your app from the App Store Connect [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/) page and select "Capabilites" and turn on Push Notifications then click "Save"
- Use the [Push Notifications Console](https://developer.apple.com/notifications/push-notifications-console/) to send a test message to your app.

### Android


## License

This software is licensed under the
[GNU Lesser General Public License v3.0](https://spdx.org/licenses/LGPL-3.0-only.html),
with a [linking exception](https://spdx.org/licenses/LGPL-3.0-linking-exception.html)
to clarify that distribution to restricted environments (e.g., app stores) is permitted.
