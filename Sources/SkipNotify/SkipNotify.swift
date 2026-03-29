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
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.os.Messenger
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
#endif

private let logger: Logger = Logger(subsystem: "skip.notify", category: "SkipNotify") // adb logcat '*:S' 'skip.notify.SkipNotify:V'

/// Cross-platform push notification support.
///
/// On iOS, uses the native `UserNotifications` framework and APNs.
/// On Android, interfaces directly with Google Mobile Services (GMS)
/// via the C2DM registration intent, without requiring the
/// `com.google.firebase:firebase-messaging` library.
///
/// ```swift
/// let token = try await SkipNotify.shared.fetchNotificationToken()
/// ```
public class SkipNotify {
    public static let shared = SkipNotify()

    private init() {
    }

    // MARK: - GMS Availability

    /// Returns `true` if Google Mobile Services (GMS) is available on the device.
    ///
    /// On iOS, always returns `false`. On Android, checks whether the device
    /// has a service that can handle the C2DM registration intent.
    public var isGMSAvailable: Bool {
        #if SKIP
        return Self.checkGMSAvailable()
        #else
        return false
        #endif
    }

    /// Returns a human-readable description of the GMS availability status.
    ///
    /// On iOS, returns `"GMS not applicable (iOS)"`.
    /// On Android, returns either `"GMS available"` or `"GMS not available"`.
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
    /// On Android, requests an FCM registration token directly from GMS
    /// using the C2DM registration intent.
    ///
    /// - Parameter senderID: The GCM/FCM sender ID (project number) for the
    ///   Firebase project. Required on Android; ignored on iOS.
    /// - Returns: The push notification token string.
    /// - Throws: `SkipNotifyError` if token retrieval fails or GMS is unavailable.
    public func fetchNotificationToken(senderID: String = "") async throws -> String {
        #if SKIP
        guard Self.checkGMSAvailable() else {
            throw SkipNotifyError(message: "Google Mobile Services (GMS) is not available on this device")
        }
        return try await Self.requestToken(senderID: senderID)
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

    // MARK: - Android GMS Implementation

    #if SKIP
    /// The C2DM registration intent action.
    private static let ACTION_C2DM_REGISTER = "com.google.android.c2dm.intent.REGISTER"

    /// Checks whether the device has a GMS service that can handle C2DM registration.
    private static func checkGMSAvailable() -> Bool {
        guard let context = ProcessInfo.processInfo.androidContext else {
            return false
        }
        let intent = Intent(ACTION_C2DM_REGISTER)
        intent.setPackage("com.google.android.gms")
        let resolveInfo = context.packageManager.resolveService(intent, PackageManager.GET_RESOLVED_FILTER)
        return resolveInfo != nil
    }

    /// Requests a registration token from GMS using the C2DM registration intent.
    ///
    /// This sends an intent to `com.google.android.gms` with a `Messenger` callback.
    /// GMS responds asynchronously with a `Message` containing the registration token
    /// in `msg.data.getString("registration_id")`.
    private static func requestToken(senderID: String) async throws -> String {
        guard let context = ProcessInfo.processInfo.androidContext else {
            throw SkipNotifyError(message: "Android context not available")
        }

        return try await suspendCancellableCoroutine { continuation in
            let handler = RegistrationHandler(continuation: continuation)
            let messenger = Messenger(handler)

            let intent = Intent(ACTION_C2DM_REGISTER)
            intent.setPackage("com.google.android.gms")
            intent.putExtra("app", android.app.PendingIntent.getBroadcast(context, 0, Intent(), android.app.PendingIntent.FLAG_IMMUTABLE))
            intent.putExtra("google.messenger", messenger)
            if !senderID.isEmpty {
                intent.putExtra("sender", senderID)
            }

            do {
                context.startService(intent)
                logger.info("C2DM registration intent sent to GMS")
            } catch {
                logger.error("Failed to send C2DM registration intent: \(error)")
                continuation.resumeWithException(SkipNotifyError(message: "Failed to send registration intent: \(error)") as Throwable)
            }
        }
    }

    /// Handler that receives the GMS C2DM registration response.
    private class RegistrationHandler: Handler {
        let continuation: kotlin.coroutines.Continuation<String>

        init(continuation: kotlin.coroutines.Continuation<String>) {
            super.init(Looper.getMainLooper())
            self.continuation = continuation
        }

        override func handleMessage(_ msg: Message) {
            let data = msg.data
            let registrationId = data?.getString("registration_id")
            let error = data?.getString("error")

            if let token = registrationId, !token.isEmpty {
                logger.info("Received GMS registration token (\(token.count) chars)")
                continuation.resume(token)
            } else if let errorMsg = error {
                logger.error("GMS registration failed: \(errorMsg)")
                continuation.resumeWithException(SkipNotifyError(message: "GMS registration failed: \(errorMsg)") as Throwable)
            } else {
                logger.error("GMS registration returned empty response")
                continuation.resumeWithException(SkipNotifyError(message: "GMS registration returned empty response") as Throwable)
            }
        }
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
