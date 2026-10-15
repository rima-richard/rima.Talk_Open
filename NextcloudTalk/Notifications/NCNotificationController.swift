//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UserNotifications

// MARK: - Notification names

extension NSNotification.Name {
    static let NCNotificationControllerWillPresent = Notification.Name(rawValue: "NCNotificationControllerWillPresentNotification")
    static let NCLocalNotificationJoinChat = Notification.Name(rawValue: "NCLocalNotificationJoinChatNotification")
}

@objc extension NSNotification {
    public static let NCNotificationControllerWillPresent = Notification.Name.NCNotificationControllerWillPresent
    public static let NCLocalNotificationJoinChat = Notification.Name.NCLocalNotificationJoinChat
}

@objcMembers
public class NCNotificationController: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NCNotificationController()

    @available(*, renamed: "shared")
    static func sharedInstance() -> NCNotificationController {
        return NCNotificationController.shared
    }

    // MARK: - Notification action identifiers

    public static let actionShareRecording = "SHARE_RECORDING"
    public static let actionDismissRecordingNotification = "DISMISS_RECORDING_NOTIFICATION"
    public static let actionReplyToChat = "REPLY_CHAT"
    public static let actionFederationInvitationAccept = "ACCEPT_FEDERATION_INVITATION"
    public static let actionFederationInvitationReject = "REJECT_FEDERATION_INVITATION"

    private let notificationCenter = UNUserNotificationCenter.current()
    private var serverNotificationsAttempts: [AnyHashable: Any] = [:] // notificationId -> get attempts

    override init() {
        super.init()

        self.notificationCenter.delegate = self
    }

    public func requestAuthorization() {
        let authOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
        self.notificationCenter.requestAuthorization(options: authOptions) { granted, _ in
            if granted {
                NSLog("User notifications permission granted.")
            } else {
                NSLog("User notifications permission denied.")
            }
        }
    }

    public func processBackgroundPushNotification(_ pushNotification: NCPushNotification?) {
        guard let pushNotification else {
            return
        }

        switch pushNotification.type {
        case .delete:
            self.removeNotification(withNotificationIds: [NSNumber(value: pushNotification.notificationId)], forAccountId: pushNotification.accountId, withCompletionBlock: nil)
        case .deleteAll:
            self.removeAllNotifications(forAccountId: pushNotification.accountId)
        case .deleteMultiple:
            self.removeNotification(withNotificationIds: pushNotification.notificationIds as? [NSNumber], forAccountId: pushNotification.accountId, withCompletionBlock: nil)
        default:
            NSLog("Push Notification of an unknown type received")
        }
    }

    // Only call a notification a video call when CallKit has confirmed video metadata.
    // Missing/older metadata retains the existing generic missed-call wording.
    static func missedCallBody(displayName: String, hasVideo: Bool) -> String {
        if hasVideo {
            let format = NSLocalizedString("Missed video call from %@", comment: "'%@' being the display name of the caller")
            return "📹 \(String(format: format, displayName))"
        }
        let format = NSLocalizedString("Missed call from %@", comment: "'%@' being the display name of the caller")
        return "☎️ \(String(format: format, displayName))"
    }

    @objc(showLocalNotification:withUserInfo:)
    public func show(_ type: NCLocalNotificationType, withUserInfo userInfo: [AnyHashable: Any]) {
        let content = UNMutableNotificationContent()

        switch type {
        case .missedCall:
            content.body = Self.missedCallBody(displayName: userInfo[stringForKey: "displayName"] ?? "", hasVideo: userInfo["hasVideo"] as? Bool == true)
            content.userInfo = userInfo
        case .cancelledCall:
            let cancelledCallString = NSLocalizedString("Cancelled call from another account", comment: "")
            content.body = "☎️ \(cancelledCallString)"
            content.userInfo = userInfo
        case .failedSendChat:
            content.body = NSLocalizedString("Failed to send message", comment: "")
            content.userInfo = userInfo
        case .callFromOldAccount:
            content.body = NSLocalizedString("Received call from an old account", comment: "")
            content.userInfo = userInfo
        case .failedToShareRecording:
            content.body = NSLocalizedString("Failed to share recording", comment: "")
            content.userInfo = userInfo
        case .failedToAcceptInvitation:
            content.body = NSLocalizedString("Failed to accept invitation", comment: "")
            content.userInfo = userInfo
        case .recordingConsentRequired:
            let consentRequiredTranslation = NSLocalizedString("Recording consent required for joining the call %@", comment: "'%@' being the display name of the call")
            let consentRequiredString = String(format: consentRequiredTranslation, userInfo[stringForKey: "displayName"] ?? "")
            content.body = "⚠️ \(consentRequiredString)"
            content.userInfo = userInfo
        case .endToEndEncryptionUnsupported:
            let endToEndEncryptionUnsupported = NSLocalizedString("Calling is currently not supported because end-to-end-encryption is enabled on the server", comment: "")
            content.body = "⚠️ \(endToEndEncryptionUnsupported)"
            content.userInfo = userInfo
        default:
            break
        }

        let identifier = String(format: "Notification-%f", Date().timeIntervalSince1970)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        self.notificationCenter.add(request, withCompletionHandler: nil)

        let accountId = userInfo["accountId"] as? String ?? ""
        NCDatabaseManager.sharedInstance().increaseUnreadBadgeNumber(forAccountId: accountId)
        self.updateAppIconBadgeNumber()
    }

    public func showLocalNotificationForIncomingCall(withPushNotificaion pushNotification: NCPushNotification) {
        let content = UNMutableNotificationContent()
        content.body = pushNotification.bodyForRemoteAlerts()
        content.threadIdentifier = pushNotification.roomToken
        content.sound = .default

        var userInfo: [AnyHashable: Any] = [:]
        userInfo["pushNotification"] = pushNotification.jsonString
        userInfo["accountId"] = pushNotification.accountId
        userInfo["notificationId"] = pushNotification.notificationId
        content.userInfo = userInfo

        let identifier = String(format: "Notification-%f", Date().timeIntervalSince1970)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        self.notificationCenter.add(request, withCompletionHandler: nil)

        NCDatabaseManager.sharedInstance().increaseUnreadBadgeNumber(forAccountId: pushNotification.accountId)
        self.updateAppIconBadgeNumber()
    }

    public func showIncomingCall(forPushNotification pushNotification: NCPushNotification) {
        if CallKitManager.isCallKitAvailable() {
            CallKitManager.sharedInstance().reportIncomingCall(pushNotification.roomToken, withDisplayName: NSLocalizedString("Incoming call", comment: ""), forAccountId: pushNotification.accountId)
        } else {
            CallKitManager.sharedInstance().reportIncomingCallForNonCallKitDevices(withPushNotification: pushNotification)
        }
    }

    public func showIncomingCallForOldAccount() {
        CallKitManager.sharedInstance().reportIncomingCallForOldAccount()
    }

    public func showLocalNotification(forChatNotification notification: NCNotification, forAccountId accountId: String) {
        let content = UNMutableNotificationContent()
        content.title = notification.chatMessageTitle
        content.body = notification.message
        content.summaryArgument = notification.chatMessageAuthor
        content.threadIdentifier = notification.roomToken
        content.sound = .default

        // Currently not supported for local notifications
        // content.categoryIdentifier = "CATEGORY_CHAT"

        var userInfo: [AnyHashable: Any] = [:]
        userInfo["roomToken"] = notification.roomToken
        userInfo["accountId"] = accountId
        userInfo["notificationId"] = notification.notificationId
        userInfo["localNotificationType"] = NCLocalNotificationType.chatNotification.rawValue
        content.userInfo = userInfo

        let identifier = "ChatNotification-\(notification.notificationId)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        self.notificationCenter.add(request, withCompletionHandler: nil)

        NCDatabaseManager.sharedInstance().increaseUnreadBadgeNumber(forAccountId: accountId)
        self.updateAppIconBadgeNumber()
    }

    private func updateAppIconBadgeNumber() {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = NCDatabaseManager.sharedInstance().numberOfUnreadNotifications()
        }
    }

    public func removeAllNotifications(forAccountId accountId: String) {
        // Check in pending notifications
        self.notificationCenter.getPendingNotificationRequests { requests in
            for notificationRequest in requests {
                let notificationAccountId = notificationRequest.content.userInfo["accountId"] as? String
                if let notificationAccountId, notificationAccountId == accountId {
                    self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationRequest.identifier])
                }
            }
        }
        // Check in delivered notifications
        self.notificationCenter.getDeliveredNotifications { notifications in
            for notification in notifications {
                let notificationAccountId = notification.request.content.userInfo["accountId"] as? String
                if let notificationAccountId, notificationAccountId == accountId {
                    self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
                }
            }
        }

        NCDatabaseManager.sharedInstance().resetUnreadBadgeNumber(forAccountId: accountId)
        self.updateAppIconBadgeNumber()
    }

    private func removeNotification(withNotificationIds notificationIds: [NSNumber]?, forAccountId accountId: String, withCompletionBlock completion: (() -> Void)?) {
        guard let notificationIds else {
            completion?()
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "decreaseUnreadBadgeNumberForAccountId")

        let removeNotification: (UNNotificationRequest, Bool) -> Void = { notificationRequest, isPending in
            let notificationAccountId = notificationRequest.content.userInfo["accountId"] as? String
            let notificationId = (notificationRequest.content.userInfo["notificationId"] as? NSNumber)?.intValue ?? 0

            guard notificationAccountId == accountId else {
                return
            }

            if notificationIds.contains(NSNumber(value: notificationId)) {
                if isPending {
                    self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationRequest.identifier])
                } else {
                    self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [notificationRequest.identifier])
                }

                NCDatabaseManager.sharedInstance().decreaseUnreadBadgeNumber(forAccountId: accountId)
            }
        }

        let notificationsGroup = DispatchGroup()

        notificationsGroup.enter()
        // Check in pending notifications
        self.notificationCenter.getPendingNotificationRequests { requests in
            for notificationRequest in requests {
                if bgTask.isExpired {
                    notificationsGroup.leave()
                    return
                }
                removeNotification(notificationRequest, true)
            }

            self.updateAppIconBadgeNumber()
            notificationsGroup.leave()
        }

        notificationsGroup.enter()
        // Check in delivered notifications
        self.notificationCenter.getDeliveredNotifications { notifications in
            for notification in notifications {
                if bgTask.isExpired {
                    notificationsGroup.leave()
                    return
                }
                removeNotification(notification.request, false)
            }

            self.updateAppIconBadgeNumber()
            notificationsGroup.leave()
        }

        notificationsGroup.notify(queue: .main) {
            completion?()
            bgTask.stopBackgroundTask()
        }
    }

    public func checkNotificationExistance(completionBlock block: ((_ error: Error?) -> Void)?) {
        let notificationsGroup = DispatchGroup()

        for account in NCDatabaseManager.sharedInstance().allAccounts() {
            if !NCDatabaseManager.sharedInstance().serverHasNotificationsCapability(.exists, forAccountId: account.accountId) {
                continue
            }

            notificationsGroup.enter()

            self.notificationCenter.getDeliveredNotifications { notifications in
                var notificationIdsOnDevice: [NSNumber] = []

                // TODO: Instead of storing just the IDs, we can also store the identifier and directly
                // remove the notification instead of iterating again removeNotificationWithNotificationIds
                for notification in notifications {
                    let notificationRequest = notification.request
                    let notificationAccountId = notificationRequest.content.userInfo["accountId"] as? String
                    let notificationId = (notificationRequest.content.userInfo["notificationId"] as? NSNumber)?.intValue ?? 0

                    if notificationAccountId != account.accountId {
                        continue
                    }

                    notificationIdsOnDevice.append(NSNumber(value: notificationId))
                }

                if notificationIdsOnDevice.isEmpty {
                    // No notifications for this account are currently shown on the system -> no need to check anything
                    notificationsGroup.leave()
                    return
                }

                NCAPIController.sharedInstance().checkNotificationExistance(withIds: notificationIdsOnDevice.map { $0.intValue }, forAccount: account) { notificationIds, error in
                    if error != nil {
                        notificationsGroup.leave()
                        return
                    }

                    // Remove all notificationIds which are still on the server
                    if let notificationIds {
                        for notificationId in notificationIds {
                            notificationIdsOnDevice.removeAll { $0.intValue == notificationId }
                        }
                    }

                    // In case there are still notifications on the device (that are not on the server anymore) remove them
                    if notificationIdsOnDevice.isEmpty {
                        notificationsGroup.leave()
                        return
                    }

                    self.removeNotification(withNotificationIds: notificationIdsOnDevice, forAccountId: account.accountId) {
                        notificationsGroup.leave()
                    }
                }
            }
        }

        notificationsGroup.notify(queue: .main) {
            // Notify backgroundFetch that we're finished
            block?(nil)
        }
    }

    @nonobjc
    public func checkNotificationExistance() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.checkNotificationExistance { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenter delegate

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Called when a notification is delivered to a foreground app.
        NotificationCenter.default.post(name: .NCNotificationControllerWillPresent, object: self, userInfo: nil)
        completionHandler([.list, .banner])

        // Remove the notification from Notification Center if it is from the active account
        let notificationAccountId = notification.request.content.userInfo["accountId"] as? String
        if let notificationAccountId, NCDatabaseManager.sharedInstance().activeAccount().accountId == notificationAccountId {
            self.removeAllNotifications(forAccountId: notificationAccountId)
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let notificationRequest = response.notification.request
        let userInfo = notificationRequest.content.userInfo

        // A remote payload cannot declare itself local or assert an account identity.
        if Self.isLocallyScheduled(notificationRequest.trigger) {
            if let text = userInfo["pushNotification"] as? String,
               let accountId = userInfo["accountId"] as? String,
               let push = NCPushNotification(fromDecryptedString: text, withAccountId: accountId) {
                self.handlePushNotificationResponse(push)
            } else {
                self.handleLocalNotificationResponse(userInfo)
            }
            completionHandler()
            return
        }

        var accounts: [TalkAccount] = []
        for case let account as TalkAccount in TalkAccount.allObjects() { accounts.append(account) }
        guard let push = NCPushNotificationsUtils.verifiedPushNotification(from: userInfo, accounts: accounts),
              let storedAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: push.accountId) else {
            completionHandler()
            return
        }
        let account = TalkAccount(value: storedAccount)
        // Fetch authoritative actions from the signed notification's account, never from userInfo.
        let task = NCAPIController.shared.getServerNotification(withId: push.notificationId, forAccount: account) { notification, _, error in
            let serverNotification = error == nil && Self.matches(notification, push: push) ? notification : nil
            self.handleVerifiedResponse(response, push: push, notification: serverNotification, account: account)
            completionHandler()
        }
        if task == nil {
            self.handleVerifiedResponse(response, push: push, notification: nil, account: account)
            completionHandler()
        }
    }

    static func isLocallyScheduled(_ trigger: UNNotificationTrigger?) -> Bool {
        return trigger is UNTimeIntervalNotificationTrigger || trigger is UNCalendarNotificationTrigger
    }

    static func matches(_ notification: NCNotification?, push: NCPushNotification) -> Bool {
        guard let notification, notification.notificationId == push.notificationId,
              notification.app == push.app else { return false }
        // Federation object IDs describe invitations rather than conversation tokens.
        if push.type != .federation, let room = push.roomToken, !room.isEmpty {
            return notification.roomToken == room
        }
        return true
    }

    private func handleVerifiedResponse(_ response: UNNotificationResponse, push: NCPushNotification, notification: NCNotification?, account: TalkAccount) {
        push.threadId = notification?.threadId ?? 0
        if let textInputResponse = response as? UNTextInputNotificationResponse, push.type == .chat {
            push.responseUserText = textInputResponse.userText
            self.handlePushNotificationResponse(withUserText: push)
        } else if push.type == .recording {
            self.handlePushNotificationResponseForRecording(notification, withActionIdentifier: response.actionIdentifier, forAccount: account)
        } else if push.type == .federation {
            self.handlePushNotificationResponseForFederation(notification, withActionIdentifier: response.actionIdentifier, forAccount: account)
        } else if push.type == .reminder {
            self.handlePushNotificationResponseForReminder(notification, withActionIdentifier: response.actionIdentifier, forAccount: account)
        } else {
            self.handlePushNotificationResponse(push)
        }
    }

    private func handlePushNotificationResponse(withUserText pushNotification: NCPushNotification) {
        NSLog("Received push-notification with user input -> sending chat message")

        guard let pushAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: pushNotification.accountId) else {
            return
        }

        let application = UIApplication.shared
        var sendTask: UIBackgroundTaskIdentifier = .invalid
        sendTask = application.beginBackgroundTask {
            application.endBackgroundTask(sendTask)
            sendTask = .invalid
        }

        DispatchQueue.global().async {
            NCAPIController.sharedInstance().sendChatMessage(pushNotification.responseUserText, toRoom: pushNotification.roomToken, threadTitle: nil, replyTo: -1, referenceId: nil, silently: false, forAccount: pushAccount) { error in
                if let error {
                    NSLog("Could not send chat message. Error: %@", error.description)

                    // Display local push-notification to inform user
                    var userInfo: [AnyHashable: Any] = [:]
                    userInfo["roomToken"] = pushNotification.roomToken
                    userInfo["localNotificationType"] = NCLocalNotificationType.failedSendChat.rawValue
                    userInfo["accountId"] = pushNotification.accountId
                    userInfo["responseUserText"] = pushNotification.responseUserText

                    NCNotificationController.sharedInstance().show(.failedSendChat, withUserInfo: userInfo)
                } else {
                    // We replied to the message, so we can assume, we read it as well
                    NCDatabaseManager.sharedInstance().decreaseUnreadBadgeNumber(forAccountId: pushNotification.accountId)
                    self.updateAppIconBadgeNumber()
                    if let room = NCDatabaseManager.sharedInstance().room(withToken: pushNotification.roomToken, forAccountId: pushNotification.accountId) {
                        NCIntentController.sharedInstance().donateSendMessageIntent(for: room)
                    }
                }

                application.endBackgroundTask(sendTask)
                sendTask = .invalid
            }
        }
    }

    private func handlePushNotificationResponseForFederation(_ serverNotification: NCNotification?, withActionIdentifier actionIdentifier: String, forAccount account: TalkAccount?) {
        guard let account, let serverNotification else {
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "handlePushNotificationResponseForFederation") { _ in
            NCLog.log("ExpirationHandler called - handlePushNotificationResponseForFederation")
        }

        if actionIdentifier == NCNotificationController.actionFederationInvitationAccept {
            let invitation = FederationInvitation(notification: serverNotification, for: account.accountId)

            NCAPIController.sharedInstance().acceptFederationInvitation(for: account.accountId, with: invitation.invitationId) { success in
                if !success {
                    var userInfo: [AnyHashable: Any] = [:]
                    userInfo["roomToken"] = serverNotification.roomToken
                    userInfo["localNotificationType"] = NCLocalNotificationType.failedToAcceptInvitation.rawValue
                    userInfo["accountId"] = account.accountId

                    self.show(.failedToAcceptInvitation, withUserInfo: userInfo)
                }

                NCDatabaseManager.sharedInstance().decreasePendingFederationInvitation(forAccountId: account.accountId)

                bgTask.stopBackgroundTask()
            }
        } else if actionIdentifier == NCNotificationController.actionFederationInvitationReject {
            let invitation = FederationInvitation(notification: serverNotification, for: account.accountId)

            NCAPIController.sharedInstance().rejectFederationInvitation(for: account.accountId, with: invitation.invitationId) { _ in
                NCDatabaseManager.sharedInstance().decreasePendingFederationInvitation(forAccountId: account.accountId)
                bgTask.stopBackgroundTask()
            }
        } else {
            bgTask.stopBackgroundTask()

            let alert = UIAlertController(title: serverNotification.subject, message: serverNotification.message, preferredStyle: .alert)

            for notificationAction in serverNotification.notificationActions {
                let tempButton = UIAlertAction(title: notificationAction.actionLabel, style: .default) { _ in
                    NCDatabaseManager.sharedInstance().decreasePendingFederationInvitation(forAccountId: account.accountId)
                    NCAPIController.sharedInstance().executeNotificationAction(notificationAction, forAccount: account, completionBlock: nil)
                }

                alert.addAction(tempButton)
            }

            DispatchQueue.main.async {
                NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            }
        }
    }

    private func handlePushNotificationResponseForRecording(_ serverNotification: NCNotification?, withActionIdentifier actionIdentifier: String, forAccount account: TalkAccount?) {
        guard let account, let serverNotification else {
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "handlePushNotificationResponseForRecording") { _ in
            NCLog.log("ExpirationHandler called - handlePushNotificationResponseForRecording")
        }

        let notificationTimeInterval = serverNotification.datetime?.timeIntervalSince1970 ?? 0
        let notificationTimestamp = String(format: "%.0f", notificationTimeInterval)

        if actionIdentifier == NCNotificationController.actionShareRecording {
            let fileParameters = serverNotification.messageRichParameters["file"] as? [AnyHashable: Any]

            guard let fileParameters, let fileId = fileParameters["id"] as? String else {
                bgTask.stopBackgroundTask()
                return
            }

            NCAPIController.sharedInstance().shareStoredRecording(withTimestamp: notificationTimestamp, withFileId: fileId, forRoom: serverNotification.roomToken, forAccount: account) { error in
                if error != nil {
                    var userInfo: [AnyHashable: Any] = [:]
                    userInfo["roomToken"] = serverNotification.roomToken
                    userInfo["localNotificationType"] = NCLocalNotificationType.failedToShareRecording.rawValue
                    userInfo["accountId"] = account.accountId

                    self.show(.failedToShareRecording, withUserInfo: userInfo)
                }

                bgTask.stopBackgroundTask()
            }
        } else if actionIdentifier == NCNotificationController.actionDismissRecordingNotification {
            NCAPIController.sharedInstance().dismissStoredRecordingNotification(withTimestamp: notificationTimestamp, forRoom: serverNotification.roomToken, forAccount: account) { _ in
                bgTask.stopBackgroundTask()
            }
        } else {
            bgTask.stopBackgroundTask()

            let alert = UIAlertController(title: serverNotification.subject, message: serverNotification.message, preferredStyle: .alert)

            let notificationActions = serverNotification.notificationActions
            for notificationAction in notificationActions {
                let tempButton = UIAlertAction(title: notificationAction.actionLabel, style: .default) { _ in
                    NCAPIController.sharedInstance().executeNotificationAction(notificationAction, forAccount: account, completionBlock: nil)
                }

                alert.addAction(tempButton)
            }

            if notificationActions.isEmpty {
                // Make sure that we have at least a way to dismiss the notification, if there are no actions
                let okButton = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
                alert.addAction(okButton)
            }

            DispatchQueue.main.async {
                NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            }
        }
    }

    private func handlePushNotificationResponseForReminder(_ serverNotification: NCNotification?, withActionIdentifier actionIdentifier: String, forAccount account: TalkAccount?) {
        guard let account, let serverNotification else {
            return
        }

        if NCRoomsManager.shared.callViewController != nil {
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "handlePushNotificationResponseForReminder") { _ in
            NCLog.log("ExpirationHandler called - handlePushNotificationResponseForReminder")
        }

        // Open the conversation for the reminder
        NCRoomsManager.shared.startChat(withRoomToken: serverNotification.roomToken)

        // After opening the notification, we need to execute the DELETE action
        for dict in serverNotification.actions {
            let notificationAction = NCNotificationAction(dictionary: dict)

            if notificationAction.actionType == .kNotificationActionTypeDelete {
                NCAPIController.sharedInstance().executeNotificationAction(notificationAction, forAccount: account) { _ in
                    bgTask.stopBackgroundTask()
                }

                return
            }
        }
        bgTask.stopBackgroundTask()
    }

    private func handlePushNotificationResponse(_ pushNotification: NCPushNotification) {
        if NCRoomsManager.shared.callViewController != nil {
            return
        }

        switch pushNotification.type {
        case .call:
            NCUserInterfaceController.sharedInstance().presentAlert(for: pushNotification)
        case .room, .chat:
            NCUserInterfaceController.sharedInstance().presentChat(for: pushNotification)
        default:
            break
        }
    }

    private func handleLocalNotificationResponse(_ notificationUserInfo: [AnyHashable: Any]) {
        if NCRoomsManager.shared.callViewController != nil {
            return
        }

        let localNotificationType = NCLocalNotificationType(rawValue: (notificationUserInfo["localNotificationType"] as? NSNumber)?.intValue ?? 0)
        guard let localNotificationType, localNotificationType.rawValue > 0 else {
            return
        }

        switch localNotificationType {
        case .missedCall, .cancelledCall, .failedSendChat, .chatNotification, .recordingConsentRequired:
            NCUserInterfaceController.sharedInstance().presentChat(forLocalNotification: notificationUserInfo)
        case .callFromOldAccount:
            NCUserInterfaceController.sharedInstance().presentSettingsViewController()
        default:
            break
        }
    }
}
