//
//  BackgroundNotifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/12/2023.
//

import SwiftUI
import BackgroundTasks
import UserNotifications

// AppDelegate is needed to handle notification taps
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Wire notification delegate
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Handle notification type, go to proper tab/subtab on tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {

        L.og.debug("userNotificationCenter.didReceive")
        let userInfo = response.notification.request.content.userInfo
        
        if let tapDestination = userInfo["tapDestination"] as? String {
            switch tapDestination {
            case "Mentions":
                UserDefaults.standard.setValue("Notifications", forKey: "selected_tab")
                UserDefaults.standard.setValue("Mentions", forKey: "selected_notifications_tab")
            case "Messages":
                UserDefaults.standard.setValue("Messages", forKey: "selected_tab")
            default:
                break
            }
        }
        completionHandler()
    }
}

// Schedule a background fetch task
func scheduleAppRefresh() {
    L.og.debug("scheduleAppRefresh()")
    let request = BGAppRefreshTaskRequest(identifier: "com.nostur.app-refresh")
    request.earliestBeginDate = .now.addingTimeInterval(60) // 60 seconds. Should maybe be longer for battery life, 5-30 minutes? Need to test
    try? BGTaskScheduler.shared.submit(request)
}

// Request permissions to send local notifications
func requestNotificationPermission(redirectToSettings:Bool = false) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
        if success {
            L.og.debug("requestNotificationPermission: success")
        }
        else {
            L.og.error("\(error?.localizedDescription ?? "Error with UNUserNotificationCenter.current().requestAuthorization")")
            DispatchQueue.main.async {
                SettingsStore.shared.receiveLocalNotifications = false
                if redirectToSettings {
                    if let appSettings = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(appSettings) {
                        UIApplication.shared.open(appSettings)
                    }
                }
            }
        }
    }
}

// Schedule a local notification for 1 or more mentions
func scheduleMentionNotification(_ mentions:[Mention]) {
    L.og.debug("scheduleMentionNotification()")
    
    // Remember timestamp so we only show newer notifications next time
    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_local_notification_timestamp")
    
    // Create the notificatgion
    let content = UNMutableNotificationContent()
    content.title = Set(mentions.map { $0.name }).formatted(.list(type: .and)) // "John and Jim"
    content.subtitle = mentions.count == 1 ? (mentions.first?.message ?? "Message") : "\(mentions.count) messages" // "What's up" or "2 messages"
    content.sound = .default
    content.userInfo = ["tapDestination": "Mentions"] // For navigating to the Notifications->Mentions tab
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

struct Mention {
    let name: String
    let message: String
}

// Schedule a local notification for 1 direct message
func scheduleDMNotification(name: String) {
    L.og.debug("scheduleDMNotification()")
    
    // Remember timestamp so we only show newer notifications next time
    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_dm_local_notification_timestamp")
    
    let content = UNMutableNotificationContent()
    content.title = name // "John"
    content.subtitle = "Direct Message"
    content.sound = .default
    content.userInfo = ["tapDestination": "Messages"] // For navigating to the DM tab
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

// The background fetch task will run this to check for new notifications
func checkForNotifications() {
    bg().perform {
        guard let account = account() else { return }
        let lastSeenPostCreatedAt = account.lastSeenPostCreatedAt
        let accountPubkey = account.publicKey

        ConnectionPool.shared.connectAll()
        
        let reqTask = ReqTask(
            subscriptionId: "BG",
            reqCommand: { taskId in
                L.og.debug("checkForNotifications.reqCommand")
                let since = NTimestamp(timestamp: Int(lastSeenPostCreatedAt))
                bg().perform {
                    NotificationsViewModel.shared.needsUpdate = true
                    
                    DispatchQueue.main.async {
                        // Mentions kinds (1,9802,30023) and DM (4)
                        req(RM.getMentions(pubkeys: [accountPubkey], kinds:[1,4,9802,30023], subscriptionId: "Notifications-BG", since: since))
                    }
                }
            },
            processResponseCommand: { taskId, relayMessage, event in
                L.og.debug("checkForNotifications.processResponseCommand")
                bg().perform {
                    NotificationsViewModel.shared.checkForUnreadMentions()
                }
            },
            timeoutCommand: { taskId in
                L.og.debug("checkForNotifications.timeoutCommand")
            }
        )
        Backlog.shared.add(reqTask)
        reqTask.fetch()
    }
}