//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitBaseChatTableViewCellTest: TestBaseRealm {

    private func layoutMessage(_ text: String, own: Bool, account: TalkAccount, room: NCRoom, id: Int) -> NCChatMessage {
        let message = NCChatMessage()
        message.messageId = id
        message.internalId = "layout-\(id)"
        message.accountId = account.accountId
        message.token = room.token
        message.actorId = own ? account.userId : "layout-colleague"
        message.actorType = "users"
        message.actorDisplayName = own ? "Ich" : "Team"
        message.message = text
        message.timestamp = 1_790_000_000 + id * 60
        return message
    }

    func testPrivateBubbleRowsFitLongTextAtPhoneWidths() throws {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let room = NCRoom()
        room.type = .oneToOne
        room.token = "layout-test"
        room.accountId = account.accountId
        let controller = BaseChatViewController(forRoom: room, withAccount: account)!

        for width: CGFloat in [320, 393, 430] {
            for own in [false, true] {
                let message = layoutMessage(String(repeating: "Ein längerer Text soll vollständig lesbar bleiben. ", count: 6),
                                            own: own, account: account, room: room, id: own ? 1 : 2)
                let cell: BaseChatTableViewCell = .fromNib()
                cell.setup(for: message, inRoom: room, forThread: nil, withAccount: account)
                let height = controller.getCellHeight(for: message, with: width - chatMessageCellAvatarHeight)
                cell.frame = CGRect(x: 0, y: 0, width: width, height: height)
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                let textView = try XCTUnwrap(cell.messageTextView)
                let requiredHeight = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
                XCTAssertGreaterThan(textView.bounds.width, 0)
                XCTAssertLessThanOrEqual(requiredHeight, textView.bounds.height + 1, "Text clipped at width \(width), own \(own)")
                XCTAssertTrue(cell.avatarButton.isHidden)
                XCTAssertTrue(cell.headerPart.isHidden)
                XCTAssertFalse(cell.footerPart.isDescendant(of: cell.bubbleView))
                XCTAssertLessThanOrEqual(cell.bubbleStackView.frame.maxY, height + 1)
                XCTAssertLessThanOrEqual(cell.bubbleView.bounds.width, width - 76 + 1)
            }
        }
    }

    func testPrivateToGroupReuseRestoresSenderAndNativeLayoutPreviews() throws {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let room = NCRoom()
        room.type = .oneToOne
        room.token = "layout-preview"
        room.accountId = account.accountId
        let controller = BaseChatViewController(forRoom: room, withAccount: account)!
        let texts = [
            ("Guten Morgen! Ist das Team schon unterwegs?", false),
            ("Ja, alles vorbereitet. 👍", true),
            ("Perfekt, danke!\nIch melde mich nach der Besprechung noch einmal.", false),
            ("Alles klar.", true)
        ]

        for style in [UIUserInterfaceStyle.light, .dark] {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 800)
            let host = UIViewController()
            host.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            // Like a real table's cells, the specimen starts below the window's top safe area.
            let preview = UIView(frame: CGRect(x: 0, y: 100, width: 393, height: 500))
            preview.overrideUserInterfaceStyle = style
            preview.backgroundColor = .systemBackground
            host.view.addSubview(preview)
            var y: CGFloat = 16
            for (index, item) in texts.enumerated() {
                let message = layoutMessage(item.0, own: item.1, account: account, room: room, id: index + 10)
                let cell: BaseChatTableViewCell = .fromNib()
                cell.overrideUserInterfaceStyle = style
                var height: CGFloat = 0
                UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                    cell.setup(for: message, inRoom: room, forThread: nil, withAccount: account)
                    height = controller.getCellHeight(for: message, with: 393 - chatMessageCellAvatarHeight)
                }
                cell.frame = CGRect(x: 0, y: y, width: 393, height: height)
                preview.addSubview(cell)
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                XCTAssertEqual(cell.traitCollection.userInterfaceStyle, style)
                let textView = try XCTUnwrap(cell.messageTextView)
                let requiredHeight = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
                XCTAssertLessThanOrEqual(requiredHeight, textView.bounds.height + 1)
                XCTAssertLessThanOrEqual(cell.bubbleView.layer.cornerRadius, cell.bubbleView.bounds.height / 2,
                                         "Short bubbles must not retain a radius from a taller layout")
                y += height
            }
            let typing = TypingIndicatorView(frame: CGRect(x: 12, y: y + 12, width: 369, height: 30))
            preview.addSubview(typing)
            typing.addTyping(userIdentifier: "layout-colleague", displayName: "Team")
            preview.layoutIfNeeded()
            preview.frame.size.height = y + 66
            host.view.layoutIfNeeded()
            // Allow TextKit's display layers to settle before taking the offscreen specimen.
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            let image = UIGraphicsImageRenderer(bounds: preview.bounds).image { context in
                preview.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = style == .dark ? "RimaChat-Layout-Dark" : "RimaChat-Layout-Light"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let message = layoutMessage("Nachricht im Team", own: false, account: account, room: room, id: 30)
        let reusedCell: BaseChatTableViewCell = .fromNib()
        reusedCell.setup(for: message, inRoom: room, forThread: nil, withAccount: account)
        reusedCell.prepareForReuse()
        room.type = .group
        reusedCell.setup(for: message, inRoom: room, forThread: nil, withAccount: account)
        XCTAssertFalse(reusedCell.avatarButton.isHidden)
        XCTAssertFalse(reusedCell.headerPart.isHidden)
    }

    // MARK: - Reactions

    private func makeReactionsView(inContainerOfWidth width: CGFloat) -> (container: UIView, reactionsView: ReactionsView) {
        // Mirrors how BaseChatTableViewCell.showReactionsPart() builds and constrains the view
        let container = UIView(frame: .init(x: 0, y: 0, width: width, height: 40))
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal

        let reactionsView = ReactionsView(frame: .init(x: 0, y: 0, width: 50, height: 30), collectionViewLayout: flowLayout)
        reactionsView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(reactionsView)

        NSLayoutConstraint.activate([
            reactionsView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            reactionsView.topAnchor.constraint(equalTo: container.topAnchor),
            reactionsView.heightAnchor.constraint(equalToConstant: 30),
            reactionsView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        ])

        return (container, reactionsView)
    }

    private func reactions(_ emojis: [String]) -> [NCChatReaction] {
        return emojis.map { NCChatReaction(reaction: $0, count: 1, userReacted: false, state: .set) }
    }

    // A cell keeps its ReactionsView across reuse, so more reactions than the previous message had
    // must widen it again instead of being clipped to the width it showed before
    func testReactionsViewWidthFollowsTheReactionsItShows() throws {
        let (container, reactionsView) = makeReactionsView(inContainerOfWidth: 1000)

        reactionsView.updateReactions(reactions: reactions(["👍", "❤️"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()
        let widthForTwo = reactionsView.frame.width

        reactionsView.updateReactions(reactions: reactions(["👍", "❤️", "😀", "🎉", "🚀"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()
        let widthForFive = reactionsView.frame.width

        XCTAssertGreaterThan(widthForFive, widthForTwo,
                             "Showing more reactions must widen the view, not clip them")
        XCTAssertEqual(widthForFive, reactionsView.collectionViewLayout.collectionViewContentSize.width, accuracy: 0.5,
                       "With enough room available, all reactions must fit without scrolling")

        reactionsView.updateReactions(reactions: reactions(["👍"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()
        XCTAssertLessThan(reactionsView.frame.width, widthForTwo,
                          "Showing fewer reactions must shrink the view again")
    }

    // Reactions that don't fit are only reachable by scrolling, which the fade is what makes visible
    func testReactionsViewFadesTheEdgeThatCanBeScrolledTowards() throws {
        let (container, reactionsView) = makeReactionsView(inContainerOfWidth: 120)

        reactionsView.updateReactions(reactions: reactions(["👍", "❤️", "😀", "🎉", "🚀"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()

        XCTAssertGreaterThan(reactionsView.contentSize.width, reactionsView.bounds.width,
                             "This case is only meaningful when the reactions don't fit")
        XCTAssertNotNil(reactionsView.layer.mask,
                        "Reactions that don't fit must be faded out at the edge they can be scrolled towards")

        let (roomyContainer, roomyReactionsView) = makeReactionsView(inContainerOfWidth: 1000)

        roomyReactionsView.updateReactions(reactions: reactions(["👍", "❤️"]))
        roomyContainer.setNeedsLayout()
        roomyContainer.layoutIfNeeded()

        XCTAssertNil(roomyReactionsView.layer.mask,
                     "Reactions that all fit must not be faded out, there is nothing to scroll to")
    }

    // A reused view must not keep the scroll position, or the new reactions start off screen
    func testReactionsViewResetsScrollPositionOnReuse() throws {
        let (container, reactionsView) = makeReactionsView(inContainerOfWidth: 120)

        reactionsView.updateReactions(reactions: reactions(["👍", "❤️", "😀", "🎉", "🚀"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()

        reactionsView.setContentOffset(.init(x: 80, y: 0), animated: false)
        XCTAssertEqual(reactionsView.contentOffset.x, 80)

        reactionsView.updateReactions(reactions: reactions(["🚀", "🎉", "😀"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()

        XCTAssertEqual(reactionsView.contentOffset.x, 0,
                       "A view showing another message's reactions must start at the first one")
    }

    func testSharedDeckCardQuote() throws {
        let deckObject = """
{
    "actor": {
        "type": "user",
        "id": "admin",
        "name": "admin"
    },
    "object": {
        "id": "9810",
        "name": "Test",
        "boardname": "Persönlich",
        "stackname": "Offen",
        "link": "https://nextcloud-mm.local/apps/deck/card/9810",
        "type": "deck-card",
        "icon-url": "https://nextcloud-mm.local/ocs/v2.php/apps/spreed/api/v1/room/123/avatar?v=abc"
    }
}
"""

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomToken = "token"

        let room = NCRoom()
        room.token = roomToken
        room.accountId = activeAccount.accountId

        let deckMessage = NCChatMessage()
        deckMessage.messageId = 1
        deckMessage.internalId = "internal-1"
        deckMessage.token = roomToken
        deckMessage.message = "existing"
        deckMessage.messageParametersJSONString = deckObject

        // Chat message with a quote
        let quoteMessage = NCChatMessage()
        quoteMessage.message = "test"
        quoteMessage.token = roomToken
        quoteMessage.parentId = "internal-1"

        try? realm.transaction {
            realm.add(room)
            realm.add(deckMessage)
            realm.add(quoteMessage)
        }

        let deckCell: BaseChatTableViewCell = .fromNib()
        deckCell.setup(for: deckMessage, inRoom: room, forThread: nil, withAccount: activeAccount)

        let quoteCell: BaseChatTableViewCell = .fromNib()
        quoteCell.setup(for: quoteMessage, inRoom: room, forThread: nil, withAccount: activeAccount)
    }

}
