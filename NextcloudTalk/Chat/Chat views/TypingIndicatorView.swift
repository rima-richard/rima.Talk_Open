//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine
import SwiftyAttributes

@objcMembers class TypingIndicatorView: UIView, SLKVisibleViewProtocol {
    private class TypingUser {
        var userIdentifier: String
        var displayName: String
        var lastUpdate: TimeInterval

        init(userIdentifier: String, displayName: String) {
            self.userIdentifier = userIdentifier
            self.displayName = displayName
            self.lastUpdate = Date().timeIntervalSinceReferenceDate
        }

        public func updateTimestamp() {
            self.lastUpdate = Date().timeIntervalSinceReferenceDate
        }
    }

    dynamic var isVisible: Bool = false {
        didSet { updateDotsAnimation() }
    }

    private(set) var typingDotsView = UIView()
    private var typingDots: [UIView] = []

    private var typingUsers: [TypingUser] = []
    private var previousUpdateTimestamp: TimeInterval = .zero
    private var updateTimer: Timer?
    private var removeTimer: Timer?

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var typingLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("TypingIndicatorView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.backgroundColor = .clear

        typingLabel.text = ""
        typingLabel.adjustsFontForContentSizeCategory = true
        setupTypingDots()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(updateDotsAnimation), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(updateDotsAnimation), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(stopDotsAnimation), name: UIApplication.willResignActiveNotification, object: nil)

        removeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            self?.checkInactiveTypingUsers()
        })
    }

    deinit {
        self.removeTimer?.invalidate()
        self.updateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDotsAnimation()
    }

    private func setupTypingDots() {
        typingDotsView.translatesAutoresizingMaskIntoConstraints = false
        typingDotsView.backgroundColor = .secondarySystemBackground
        typingDotsView.layer.cornerRadius = 12
        typingDotsView.isHidden = true
        typingDotsView.accessibilityElementsHidden = true
        contentView.addSubview(typingDotsView)

        // Replace the nib's label-only leading edge with a small bubble followed by the existing names.
        contentView.constraints.filter {
            $0.firstItem as? UIView === typingLabel && $0.firstAttribute == .leading
        }.forEach { $0.isActive = false }
        NSLayoutConstraint.activate([
            typingDotsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            typingDotsView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            typingDotsView.widthAnchor.constraint(equalToConstant: 44),
            typingDotsView.heightAnchor.constraint(equalToConstant: 24),
            typingLabel.leadingAnchor.constraint(equalTo: typingDotsView.trailingAnchor, constant: 8)
        ])

        for index in 0..<3 {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = .secondaryLabel
            dot.layer.cornerRadius = 3
            typingDotsView.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6),
                dot.centerYAnchor.constraint(equalTo: typingDotsView.centerYAnchor),
                dot.leadingAnchor.constraint(equalTo: typingDotsView.leadingAnchor, constant: CGFloat(9 + index * 10))
            ])
            typingDots.append(dot)
        }
    }

    @objc private func stopDotsAnimation() {
        typingDots.forEach { $0.layer.removeAnimation(forKey: "typingPulse") }
    }

    @objc private func updateDotsAnimation() {
        typingDotsView.isHidden = !isVisible
        guard isVisible, window?.windowScene?.activationState == .foregroundActive,
              !UIAccessibility.isReduceMotionEnabled else {
            stopDotsAnimation()
            return
        }
        for (index, dot) in typingDots.enumerated() where dot.layer.animation(forKey: "typingPulse") == nil {
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0.35, 1, 0.35]
            pulse.keyTimes = [0, 0.5, 1]
            pulse.duration = 1.2
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.18
            pulse.repeatCount = .infinity
            dot.layer.add(pulse, forKey: "typingPulse")
        }
    }

    internal func updateTypingIndicator() {
        if self.typingUsers.isEmpty {
            // Just hide the label to have a nice animation. Otherwise we would animate an empty label/space
            self.isVisible = false
        } else {
            var localizedAttributedString: NSAttributedString?

            if self.typingUsers.count == 1 {
                let unformattedAttributedString = NSLocalizedString("%@ is typing…", comment: "Alice is typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel))

            } else if self.typingUsers.count == 2 {
                let unformattedAttributedString = NSLocalizedString("%1$@ and %2$@ are typing…", comment: "Alice and Bob are typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[1].displayName.withTextColor(.secondaryLabel))

            } else if self.typingUsers.count == 3 {
                let unformattedAttributedString = NSLocalizedString("%1$@, %2$@ and %3$@ are typing…", comment: "Alice, Bob and Charlie are typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[1].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[2].displayName.withTextColor(.secondaryLabel))

            } else {
                let othersCount = self.typingUsers.count - 3

                // Resolve the plural form of the string first, passing the name placeholders through
                // unchanged, so the attributed display names can still be substituted afterwards.
                let pluralFormat = String.localizedStringWithFormat(
                    NSLocalizedString("%1$@, %2$@, %3$@ and %4$ld others are typing…", comment: "Alice, Bob, Charlie and 3 others are typing…"),
                    "%1$@", "%2$@", "%3$@", othersCount)

                let unformattedAttributedString = pluralFormat.withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[1].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[2].displayName.withTextColor(.secondaryLabel))
            }

            if let localizedAttributedString {
                UIView.transition(with: self.typingLabel,
                                  duration: 0.2,
                                  options: .transitionCrossDissolve,
                                  animations: {
                    self.typingLabel.attributedText = localizedAttributedString.withFont(.preferredFont(forTextStyle: .caption1))
                }, completion: nil)

                self.isVisible = true
            } else {
                self.isVisible = false
            }
        }

        self.previousUpdateTimestamp = Date().timeIntervalSinceReferenceDate
    }

    private func updateTypingIndicatorDebounced() {
        // There's already an update planned, no need to do that again
        if updateTimer != nil {
            return
        }

        let currentUpdateTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate

        // Update the typing indicator at max. every second
        let timestampDiff = currentUpdateTimestamp - previousUpdateTimestamp
        if timestampDiff < 1.0 {
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 - timestampDiff, repeats: false, block: { [weak self] _ in
                self?.updateTypingIndicator()
                self?.updateTimer = nil
            })
        } else {
            self.updateTypingIndicator()
        }
    }

    func checkInactiveTypingUsers() {
        let currentUpdateTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
        var usersToRemove: [TypingUser] = []

        for typingUser in typingUsers {
            let timestampDiff = currentUpdateTimestamp - typingUser.lastUpdate

            if timestampDiff >= 15 {
                // We did not receive an update for that user in the last 15 seconds -> remove it
                usersToRemove.append(typingUser)
            }
        }

        // Remove the users. Do that after iterating typingUsers to not alter the collection while iterating
        for typingUser in usersToRemove {
            self.removeTyping(userIdentifier: typingUser.userIdentifier)
        }
    }

    func addTyping(userIdentifier: String, displayName: String) {
        let existingEntry = self.typingUsers.first(where: { $0.userIdentifier == userIdentifier })

        if existingEntry == nil {
            let newEntry = TypingUser(userIdentifier: userIdentifier, displayName: displayName)
            self.typingUsers.append(newEntry)
        } else {
            // We received another startedTyping message, so we want to restart the remove timer
            existingEntry?.updateTimestamp()
        }

        self.updateTypingIndicatorDebounced()
    }

    func removeTyping(userIdentifier: String) {
        let existingIndex = self.typingUsers.firstIndex(where: { $0.userIdentifier == userIdentifier })

        if let existingIndex = existingIndex {
            self.typingUsers.remove(at: existingIndex)
        }

        self.updateTypingIndicatorDebounced()
    }
}
