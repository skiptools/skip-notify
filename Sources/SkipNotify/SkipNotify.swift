// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if !SKIP
#if canImport(UIKit) // UNUserNotificationCenter does not exist on macOS
import UIKit
#endif
import OSLog
#else
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
#endif

private let logger: Logger = Logger(subsystem: "skip.notify", category: "SkipNotify") // adb logcat '*:S' 'skip.notify.SkipNotify:V'

/// Cross-platform push notification support.
///
/// On iOS, uses the native `UserNotifications` framework and APNs.
/// On Android, communicates directly with Google Mobile Services (GMS) via
/// the C2DM registration intent protocol to obtain FCM tokens, without
/// requiring any proprietary Firebase or Google Play Services libraries.
///
/// ```swift
/// let token = try await SkipNotify.shared.fetchNotificationToken(firebaseProjectNumber: "123456789")
/// ```
public class SkipNotify {
    public static let shared = SkipNotify()

    private init() {
    }

    // MARK: - GMS Availability

    /// Returns `true` if Google Mobile Services (GMS) is available on the device.
    ///
    /// On iOS, always returns `false`. On Android, checks whether the GMS
    /// package is installed and enabled.
    public var isGMSAvailable: Bool {
        #if SKIP
        return Self.checkGMSAvailable()
        #else
        return false
        #endif
    }

    /// Returns a human-readable description of the GMS availability status.
    public var gmsStatusDescription: String {
        #if SKIP
        return isGMSAvailable ? "GMS available" : "GMS not available"
        #else
        return "GMS not applicable (iOS)"
        #endif
    }

    // MARK: - Token Retrieval

    /// Fetches the device's push notification token.
    ///
    /// On iOS, registers with APNs and returns the device token as a hex string.
    /// On Android, requests an FCM registration token from GMS using the
    /// C2DM registration intent protocol.
    ///
    /// - Parameter firebaseProjectNumber: The numeric sender ID (project number)
    ///   from the Firebase console's Cloud Messaging settings. Required on Android
    ///   to identify which Firebase project should receive messages for this app.
    ///   Ignored on iOS (APNs uses the app's bundle ID and entitlements instead).
    /// - Returns: The push notification token string.
    /// - Throws: `SkipNotifyError` if token retrieval fails or GMS is unavailable.
    public func fetchNotificationToken(firebaseProjectNumber: String?) async throws -> String {
        #if SKIP
        guard Self.checkGMSAvailable() else {
            throw SkipNotifyError(message: "Google Mobile Services (GMS) is not available on this device")
        }
        guard let firebaseProjectNumber else {
            throw SkipNotifyError(message: "Firebase Sender ID unspecified")
        }
        return try await Self.requestToken(senderID: firebaseProjectNumber)
        #else
        #if !canImport(UIKit) // UNUserNotificationCenter does not exist on macOS
        throw SkipNotifyError(message: "UIKit required for notifications on Darwin platforms")
        #else
        UNUserNotificationCenter.current().delegate = notificationCenterDelegate

        // these notifications are added to the default UIApplicationDelegate
        // created by skip init/skip create in Main.swift;
        // other project structures will need to manually add them as so:
        /** ```
         func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
             NotificationCenter.default.post(name: NSNotification.Name("didRegisterForRemoteNotificationsWithDeviceToken"), object: application, userInfo: ["deviceToken": deviceToken])
         }

         func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
             NotificationCenter.default.post(name: NSNotification.Name("didFailToRegisterForRemoteNotificationsWithError"), object: application, userInfo: ["error": error])
         }
         ``` */
        let didRegisterNotification = NSNotification.Name("didRegisterForRemoteNotificationsWithDeviceToken")
        let didFailToRegisterNotification = NSNotification.Name("didFailToRegisterForRemoteNotificationsWithError")

        var observers: [Any] = []
        func clearObservers() {
            observers.forEach({ NotificationCenter.default.removeObserver($0) })
        }
        return try await withCheckedThrowingContinuation { continuation in
            observers += [NotificationCenter.default.addObserver(forName: didRegisterNotification, object: nil, queue: .main) { note in
                logger.log("recevied \(didRegisterNotification.rawValue) with userInfo: \(note.userInfo ?? [:])")
                guard let deviceToken = note.userInfo?["deviceToken"] as? Data else {
                    return
                }
                // hex-encoded form of the deviceToken data
                let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
                clearObservers()
                continuation.resume(returning: tokenString)
            }]
            observers += [NotificationCenter.default.addObserver(forName: didFailToRegisterNotification, object: nil, queue: .main) { note in
                logger.log("recevied \(didFailToRegisterNotification.rawValue) with userInfo: \(note.userInfo ?? [:])")
                guard let error = note.userInfo?["error"] as? Error else {
                    return
                }
                clearObservers()
                continuation.resume(throwing: error)
            }]
            Task { @MainActor in
                logger.log("calling UIApplication.shared.registerForRemoteNotifications()")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        #endif
        #endif
    }

    // MARK: - iOS Notification Delegate

    #if !SKIP
    #if canImport(UIKit)
    let notificationCenterDelegate = NotificationCenterDelegate()

    class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            logger.log("userNotificationCenter willPresent notification: \(notification)")
            return UNNotificationPresentationOptions.banner
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            logger.log("userNotificationCenter didReceive response: \(response)")
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
            logger.log("userNotificationCenter openSettingsFor notification: \(notification)")
        }

    }
    #endif
    #endif

    // MARK: - Android GMS C2DM Implementation

    #if SKIP
    /// Checks whether GMS is installed and enabled on the device.
    private static func checkGMSAvailable() -> Bool {
        guard let context = ProcessInfo.processInfo.androidContext else {
            return false
        }
        do {
            let info = context.packageManager.getPackageInfo("com.google.android.gms", 0)
            return info.applicationInfo?.enabled == true
        } catch {
            return false
        }
    }

    /// Returns the installed GMS version code, or 0 if unavailable.
    private static func gmsVersionCode() -> Int {
        guard let context = ProcessInfo.processInfo.androidContext else { return 0 }
        do {
            let info = context.packageManager.getPackageInfo("com.google.android.gms", 0)
            return info.longVersionCode.toInt()
        } catch {
            return 0
        }
    }

    /// Requests an FCM registration token from GMS using the C2DM registration
    /// intent protocol. This communicates directly with GMS without any
    /// proprietary Firebase/Google libraries.
    ///
    /// The protocol sends a `com.google.android.c2dm.intent.REGISTER` intent
    /// to GMS and receives the token back via a BroadcastReceiver listening
    /// for `com.google.android.c2dm.intent.REGISTRATION`.
    private static func requestToken(senderID: String) async throws -> String {
        /* SKIP REPLACE:
        val context = ProcessInfo.processInfo.androidContext
            ?: throw SkipNotifyError(message = "Android context not available")

        if (senderID.isEmpty()) {
            logger.warning("No senderID provided — GMS requires a valid FCM sender ID (numeric project number)")
        }

        suspendCancellableCoroutine { continuation ->
            var resumed = false

            // BroadcastReceiver to receive the C2DM registration result from GMS.
            // GMS sends the token (or error) back via the REGISTRATION broadcast.
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context, intent: Intent) {
                    if (resumed) return
                    try { ctx.unregisterReceiver(this) } catch (_: Exception) {}

                    val error = intent.getStringExtra("error")
                    if (error != null) {
                        logger.error("GMS registration error: ${error}")
                        resumed = true
                        continuation.resumeWithException(SkipNotifyError(message = "GMS registration failed: ${error}") as Throwable)
                        return
                    }

                    val token = intent.getStringExtra("registration_id")
                    if (token != null && token.isNotEmpty()) {
                        logger.info("Received FCM registration token (${token.length} chars)")
                        resumed = true
                        continuation.resume(token)
                    } else {
                        logger.error("GMS registration returned empty response (no token, no error)")
                        resumed = true
                        continuation.resumeWithException(SkipNotifyError(message = "GMS registration returned empty response") as Throwable)
                    }
                }
            }

            // Listen for the REGISTRATION result broadcast from GMS.
            val intentFilter = IntentFilter("com.google.android.c2dm.intent.REGISTRATION")
            intentFilter.addCategory(context.packageName)
            context.registerReceiver(receiver, intentFilter, android.content.Context.RECEIVER_EXPORTED)

            // PendingIntent that GMS uses to verify our app's identity.
            // GMS extracts the package name from the PendingIntent creator.
            val appPendingIntent = PendingIntent.getBroadcast(
                context, 0, Intent(), PendingIntent.FLAG_IMMUTABLE
            )

            val gmsVersion = gmsVersionCode()

            // Build and send the C2DM registration intent to GMS.
            val registrationIntent = Intent("com.google.android.c2dm.intent.REGISTER")
            registrationIntent.setPackage("com.google.android.gms")
            registrationIntent.putExtra("app", appPendingIntent)
            registrationIntent.putExtra("sender", senderID)
            registrationIntent.putExtra("subtype", senderID)
            registrationIntent.putExtra("gmsVersion", gmsVersion.toString())
            registrationIntent.putExtra("scope", "GCM")

            continuation.invokeOnCancellation {
                if (!resumed) {
                    try { context.unregisterReceiver(receiver) } catch (_: Exception) {}
                }
            }

            try {
                context.startService(registrationIntent)
                logger.info("C2DM registration intent sent to GMS (sender=${senderID}, gmsVersion=${gmsVersion})")
            } catch (e: Exception) {
                logger.error("Failed to send C2DM registration intent: ${e}")
                try { context.unregisterReceiver(receiver) } catch (_: Exception) {}
                resumed = true
                continuation.resumeWithException(SkipNotifyError(message = "Failed to send registration intent: ${e}") as Throwable)
            }
        }
        */
        return "" // placeholder for Swift compilation; replaced by SKIP REPLACE above
    }
    #endif
}

/// Thrown on notify error.
public struct SkipNotifyError: LocalizedError, CustomStringConvertible {
    let message: String

    init(message: String) {
        self.message = message
    }

    public var description: String {
        return message
    }

    public var errorDescription: String? {
        return message
    }
}

#endif
