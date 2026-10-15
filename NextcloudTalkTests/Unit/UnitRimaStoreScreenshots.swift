// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import NextcloudTalk

/// Actual app controllers with in-memory, synthetic content. Never joins a server room.
private final class StoreChatViewController: ChatViewController {
    override func viewWillAppear(_ animated: Bool) {}
    override func viewWillDisappear(_ animated: Bool) {}
    override func appDidBecomeActive(notification: Notification) {}
}

final class UnitRimaStoreScreenshots: TestBaseRealm {
    private func capture(_ controller: UIViewController, name: String, size: CGSize, scale: CGFloat) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size.width * image.scale, size.width * scale)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKeyAndVisible()
    }

    private func chat(group: Bool) throws -> UIViewController {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        updateCapabilities { $0.callEnabled = true }
        let room = NCRoom()
        room.accountId = account.accountId
        room.token = group ? "store-group" : "store-private"
        room.internalId = "\(room.token)@\(account.accountId)"
        room.name = group ? "Team Austausch" : "anna-beispiel"
        room.displayName = group ? "Team Austausch" : "Anna Beispiel"
        room.type = group ? .group : .oneToOne
        room.canStartCall = true
        let controller = try XCTUnwrap(StoreChatViewController(forRoom: room, withAccount: account))
        controller.loadViewIfNeeded()
        controller.checkRoomControlsAvailability()
        // The fixture represents the normal joined state without a network join.
        controller.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
        let texts: [(String, Bool)] = group ? [
            ("Guten Morgen zusammen! ☀️", false),
            ("Unsere Besprechung startet heute um 9 Uhr.", false),
            ("Danke für die Info. Ich bin dabei!", true),
            ("Die Unterlagen findet ihr im Teamordner.", false),
            ("Perfekt, dann bis gleich. 👍", true)
        ] : [
            ("Hallo! Hast du kurz Zeit für eine Rückfrage?", false),
            ("Ja, gern. Worum geht es?", true),
            ("Können wir die Besprechung auf 10 Uhr legen?", false),
            ("Das passt gut. Ich aktualisiere den Termin.", true),
            ("Vielen Dank! 😊", false),
            ("Bis nachher!", true)
        ]
        let now = Int(Date().timeIntervalSince1970) - 600
        let messages = texts.enumerated().map { index, item -> NCChatMessage in
            let message = NCChatMessage()
            message.messageId = index + 1
            message.internalId = "store-\(room.token)-\(index)"
            message.accountId = account.accountId
            message.token = room.token
            message.actorId = item.1 ? account.userId : "anna-beispiel"
            message.actorDisplayName = item.1 ? "Ich" : "Anna Beispiel"
            message.actorType = "users"
            message.message = item.0
            message.timestamp = now + index * 60
            return message
        }
        controller.appendMessages(messages: messages)
        controller.tableView?.reloadData()
        let root = UIViewController()
        root.title = NSLocalizedString("Conversations", comment: "")
        let navigation = NCNavigationController(rootViewController: root)
        navigation.setViewControllers([root, controller], animated: false)
        return navigation
    }

    func testCaptureNativeStoreScreens() throws {
        for (device, size, scale) in [
            ("iPhone", CGSize(width: 440, height: 956), CGFloat(3)),
            ("iPad", CGSize(width: 1032, height: 1376), CGFloat(2))
        ] {
            try capture(chat(group: false), name: "Store-\(device)-Chat", size: size, scale: scale)
            try capture(chat(group: true), name: "Store-\(device)-Team", size: size, scale: scale)
            let account = NCDatabaseManager.sharedInstance().activeAccount()
            let room = NCRoom()
            room.accountId = account.accountId
            room.token = "store-call"
            room.name = "anna-beispiel"
            room.displayName = "Anna Beispiel"
            room.type = .oneToOne
            let call = CallViewController(for: room, withAccount: account, audioOnly: true)
            call.loadViewIfNeeded()
            call.waitingView.statusLabel.text = "Warte auf Antwort …"
            try capture(call, name: "Store-\(device)-Call", size: size, scale: scale)
            call.invalidateDetailedViewTimer()
        }
    }
}
