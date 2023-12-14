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
        
        // Register background processing task here (SwiftUI doesn't support PROCESSING tasks yet, only REFRESH tasks)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.nostur.db-cleanup", using: nil) { task in
            // Downcast the parameter to a processing task as this identifier is used for a processing request.
            self.handleDatabaseCleaning(task: task as! BGProcessingTask)
        }
        
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
    
    // Delete feed entries older than one day.
    func handleDatabaseCleaning(task: BGProcessingTask) {
        L.maintenance.debug("handleDatabaseCleaning()")
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let context = DataProvider.shared().newTaskContext()
        let cleanDatabaseOperation = DatabaseCleanUpOperation(context: context)
        
        task.expirationHandler = {
            // After all operations are cancelled, the completion block below is called to set the task to complete.
            queue.cancelAllOperations()
        }

        cleanDatabaseOperation.completionBlock = {
            let success = !cleanDatabaseOperation.isCancelled
            if success {
                // Update the last clean date to the current time.
                SettingsStore.shared.lastMaintenanceTimestamp = Int(Date.now.timeIntervalSince1970)
            }
            L.maintenance.debug("cleanDatabaseOperation.completionBlock: success: \(success)")
            task.setTaskCompleted(success: success)
        }
        
        queue.addOperation(cleanDatabaseOperation)
    }
}

// Schedule a background fetch task
func scheduleAppRefresh(seconds: TimeInterval = 60.0) {
    L.og.debug("scheduleAppRefresh()")
    let request = BGAppRefreshTaskRequest(identifier: "com.nostur.app-refresh")
    request.earliestBeginDate = .now.addingTimeInterval(seconds) // 60 seconds. Should maybe be longer for battery life, 5-30 minutes? Need to test
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
    content.body = mentions.count == 1 ? (mentions.first?.message ?? "Message") : "\(mentions.count) messages" // "What's up" or "2 messages"
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
    content.body = "Direct Message"
    content.sound = .default
    content.userInfo = ["tapDestination": "Messages"] // For navigating to the DM tab
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

// The background fetch task will run this to check for new notifications
func checkForNotifications() async {
    await withCheckedContinuation { continuation in
        Task { @MainActor in
            guard !NRState.shared.activeAccountPublicKey.isEmpty else { continuation.resume(); return }
            if Importer.shared.existingIds.isEmpty {
                Importer.shared.preloadExistingIdsCache()
            }
            guard let account = try? CloudAccount.fetchAccount(publicKey: NRState.shared.activeAccountPublicKey, context: context())
            else {
                continuation.resume(); return
            }
            let accountData = account.toStruct()
            if !WebOfTrust.shared.didWoT {
                WebOfTrust.shared.loadWoT()
            }
            
            // Setup connections
            let relays:[RelayData] = CloudRelay.fetchAll(context: DataProvider.shared().viewContext).map { $0.toStruct() }
            for relay in relays {
                _ = ConnectionPool.shared.addConnection(relay)
            }
            ConnectionPool.shared.connectAll()
            bg().perform {
                let reqTask = ReqTask(
                    debounceTime: 0.05,
                    timeout: 10.0,
                    subscriptionId: "BG",
                    reqCommand: { taskId in
                        L.og.debug("checkForNotifications.reqCommand")
                        let since = NTimestamp(timestamp: Int(accountData.lastSeenPostCreatedAt))
                        bg().perform {
                            NotificationsViewModel.shared.needsUpdate = true
                            
                            DispatchQueue.main.async {
                                // Mentions kinds (1,9802,30023) and DM (4)
                                req(RM.getMentions(pubkeys: [accountData.publicKey], kinds:[1,4,9802,30023], subscriptionId: taskId, since: since))
                            }
                        }
                    },
                    processResponseCommand: { taskId, relayMessage, event in
                        L.og.debug("checkForNotifications.processResponseCommand")
                        bg().perform {
                            if let thisTask = Backlog.shared.task(with: taskId) {
                                Backlog.shared.remove(thisTask)
                            }
                        }
                        Task {
                            await NotificationsViewModel.shared.checkForUnreadMentionsBackground(accountData: accountData)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                ConnectionPool.shared.disconnectAll()
                            }
                            continuation.resume()
                        }
                    },
                    timeoutCommand: { taskId in
                        L.og.debug("checkForNotifications.timeoutCommand")
                        bg().perform {
                            if let thisTask = Backlog.shared.task(with: taskId) {
                                Backlog.shared.remove(thisTask)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            ConnectionPool.shared.disconnectAll()
                        }
                        continuation.resume()
                    }
                )
                Backlog.shared.add(reqTask)
                reqTask.fetch()
            }
        }
    }
}
