// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
import Foundation
#if !SKIP
import UIKit
import OSLog
#else
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.RemoteMessage
#endif

private let logger: Logger = Logger(subsystem: "skip.notify", category: "SkipNotify") // adb logcat '*:S' 'skip.notify.SkipNotify:V'

public class SkipNotify {
    public static let shared = SkipNotify()

    private init() {
    }

    public func fetchNotificationToken() async throws -> String {
        #if SKIP
        FirebaseMessaging.getInstance().token.await()
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
    }

    #if !SKIP
    let notificationCenterDelegate = NotificationCenterDelegate()

    class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            // Callback when app is in foreground and notification arrives
            // e.g., userNotificationCenter willPresent notification: <UNNotification: 0x1117e18f0; source: org.appfair.app.Showcase date: 2025-12-18 22:04:52 +0000, request: <UNNotificationRequest: 0x1117e1890; identifier: 8B514E79-74CD-4399-BBF5-C2F4F9663292, content: <UNNotificationContent: 0x111835400; title: <redacted>, subtitle: <redacted>, body: <redacted>, attributedBody: (null), summaryArgument: (null), summaryArgumentCount: 0, categoryIdentifier: , launchImageName: , threadIdentifier: , attachments: (), badge: (null), sound: (null), realert: 0, interruptionLevel: 1, relevanceScore: 0.00, filterCriteria: (null), screenCaptureProhibited: 0, speechLanguage: (null), trigger: <UNPushNotificationTrigger: 0x104ac3440; contentAvailable: NO, mutableContent: NO>>, intents: (
            logger.log("userNotificationCenter willPresent notification: \(notification)")
            return UNNotificationPresentationOptions.banner
        }

        // Callback when app is in background and user taps notification to open the app
        // userNotificationCenter didReceive response: <UNNotificationResponse: 0x11186c510; actionIdentifier: com.apple.UNNotificationDefaultActionIdentifier, notification: <UNNotification: 0x11186f270; source: org.appfair.app.Showcase date: 2025-12-18 22:06:22 +0000, request: <UNNotificationRequest: 0x11186f360; identifier: 79B5A08E-84D4-4A03-A7D4-ABC60B8AAF77, content: <UNNotificationContent: 0x110dccc80; title: <redacted>, subtitle: <redacted>, body: <redacted>, attributedBody: (null), summaryArgument: (null), summaryArgumentCount: 0, categoryIdentifier: , launchImageName: , threadIdentifier: , attachments: (), badge: (null), sound: (null), realert: 0, interruptionLevel: 1, relevanceScore: 0.00, filterCriteria: (null), screenCaptureProhibited: 0, speechLanguage: (null), trigger: <UNPushNotificationTrigger: 0x111ab4550; contentAvailable: NO, mutableContent: NO>>, intents: ()>>
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            logger.log("userNotificationCenter didReceive response: \(response)")
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
            logger.log("userNotificationCenter openSettingsFor notification: \(notification)")
        }

    }
    #endif
}

#endif
