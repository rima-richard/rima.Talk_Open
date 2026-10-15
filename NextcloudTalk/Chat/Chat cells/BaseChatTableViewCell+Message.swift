//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension BaseChatTableViewCell {

    func setupForMessageCell(with message: NCChatMessage) {
        if self.messageTextView == nil {
            let messageTextView = MessageBodyTextView()
            self.messageTextView = messageTextView

            messageTextView.translatesAutoresizingMaskIntoConstraints = false

            self.messageBodyView.addSubview(messageTextView)

            NSLayoutConstraint.activate([
                messageTextView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                messageTextView.rightAnchor.constraint(equalTo: self.messageBodyView.rightAnchor),
                messageTextView.topAnchor.constraint(equalTo: self.messageBodyView.topAnchor),
                messageTextView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)
            ])
        }

        guard let messageTextView = self.messageTextView else { return }

        if usesSolidOutgoingBubble, let parsed = message.parsedMarkdownForChat() {
            let text = NSMutableAttributedString(attributedString: parsed)
            text.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: text.length))
            messageTextView.attributedText = text
            messageTextView.linkTextAttributes = [.foregroundColor: UIColor.white, .underlineStyle: NSUnderlineStyle.single.rawValue]
        } else {
            messageTextView.attributedText = message.parsedMarkdownForChat()
            messageTextView.linkTextAttributes = [.foregroundColor: NCAppBranding.themeColor()]
        }
    }
}
