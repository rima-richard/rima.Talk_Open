//
// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

/// A collection-view background only. It is removed as soon as participants join;
/// remote video, screen sharing and the floating camera preview keep their own views.
final class RimaCallWaitingView: UIView {

    let avatarImageView = RimaCallAvatarImageView(frame: .zero)
    let nameLabel = UILabel()
    let statusLabel = UILabel()

    private let gradient = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let avatarContainer = UIView()
    private var avatarDiameter: NSLayoutConstraint!
    private var avatarIdentity: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        backgroundColor = RimaCallAppearance.surfaceColor
        gradient.colors = [RimaCallAppearance.surfaceColor.cgColor, RimaCallAppearance.backgroundColor.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        avatarImageView.clipsToBounds = true
        avatarImageView.isAccessibilityElement = false
        avatarContainer.addSubview(avatarImageView)

        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0
        nameLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 28, weight: .semibold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.accessibilityTraits.insert(.header)

        statusLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [nameLabel, avatarContainer, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(28, after: nameLabel)
        stack.setCustomSpacing(20, after: avatarContainer)
        contentView.addSubview(stack)

        for child in [scrollView, contentView, stack, avatarImageView] {
            child.translatesAutoresizingMaskIntoConstraints = false
        }
        avatarDiameter = avatarContainer.heightAnchor.constraint(equalToConstant: 192)
        let viewportHeight = contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        viewportHeight.priority = .defaultLow
        let contentWidth = stack.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -48)
        contentWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            viewportHeight,
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            contentWidth,
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            stack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            avatarDiameter,
            avatarImageView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            avatarImageView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            avatarImageView.widthAnchor.constraint(equalTo: avatarImageView.heightAnchor)
        ])
    }

    func configure(for room: NCRoom) {
        nameLabel.text = room.displayName
        avatarImageView.setFallbackDisplayName(room.displayName)
        let identity = "\(room.accountId):\(room.token):\(room.avatarVersion ?? ""): custom=\(room.isCustomAvatar)"
        guard avatarIdentity != identity else { return }
        avatarImageView.prepareForReuse()
        avatarImageView.setFallbackDisplayName(room.displayName)
        // A room can arrive before its participant name; keep the placeholder in that case.
        guard room.type != .oneToOne || room.name?.isEmpty == false else { return }
        avatarIdentity = identity
        avatarImageView.setAvatar(for: room)
    }

    override func layoutSubviews() {
        gradient.frame = bounds
        avatarDiameter.constant = floor(min(200, max(64, min(bounds.width * 0.52, bounds.height * 0.38))))
        super.layoutSubviews()
    }
}

@objcMembers final class RimaCallAvatarImageView: AvatarImageView {
    private let initialsLabel = UILabel()
    private var avatarDownload: SDWebImageDownloadToken?
    private var avatarRequestID = UUID()
    // Keep HTTP response metadata alongside the image. An old decoded image cache
    // cannot tell a server-generated letter avatar from an uploaded profile photo.
    private var avatarDownloader: SDWebImageDownloader?

    deinit {
        avatarDownloader?.invalidateSessionAndCancel(true)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureInitials()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureInitials()
    }

    private func configureInitials() {
        initialsLabel.textAlignment = .center
        initialsLabel.textColor = .white
        initialsLabel.backgroundColor = RimaCallAppearance.avatarColor
        initialsLabel.adjustsFontSizeToFitWidth = true
        initialsLabel.minimumScaleFactor = 0.6
        initialsLabel.isAccessibilityElement = false
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initialsLabel)
        NSLayoutConstraint.activate([
            initialsLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            initialsLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            initialsLabel.topAnchor.constraint(equalTo: topAnchor),
            initialsLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateInitialsVisibility()
    }

    static func initials(for name: String?) -> String {
        let words = (name ?? "").split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first?.first else { return "?" }
        if words.count > 1, let last = words.last?.first {
            return String([first, last]).uppercased()
        }
        return String(first).uppercased()
    }

    func setFallbackDisplayName(_ name: String?) {
        initialsLabel.text = Self.initials(for: name)
        updateInitialsVisibility()
    }

    override func prepareForReuse() {
        avatarRequestID = UUID()
        avatarDownload?.cancel()
        avatarDownload = nil
        super.prepareForReuse()
        initialsLabel.text = "?"
    }

    override func setAvatar(for room: NCRoom) {
        prepareForReuse()
        setFallbackDisplayName(room.displayName)
        if room.type == .oneToOne, room.remoteServer?.isEmpty != false,
           let userId = room.name, !userId.isEmpty, let account = room.account {
            loadUserAvatar(for: userId, account: account)
        } else {
            super.setAvatar(for: room)
        }
    }

    override func setActorAvatar(forId actorId: String?, withType actorType: String?, withDisplayName actorDisplayName: String?, withRoomToken roomToken: String?, using account: TalkAccount) {
        prepareForReuse()
        setFallbackDisplayName(actorDisplayName)
        if actorType == "users", let actorId, !actorId.isEmpty {
            loadUserAvatar(for: actorId, account: account)
        } else if actorType != AttendeeType.guest.rawValue && actorType != AttendeeType.email.rawValue {
            // Keep the existing federation, bot, group and deleted-user handling.
            super.setActorAvatar(forId: actorId, withType: actorType, withDisplayName: actorDisplayName, withRoomToken: roomToken, using: account)
        }
    }

    private func loadUserAvatar(for userId: String, account: TalkAccount) {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let modifier = NCAPIController.sharedInstance().getRequestModifier(forAccount: account)
        else { return }
        var urlString = "\(account.server)/index.php/avatar/\(encodedUserId)/512"
        let capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        if traitCollection.userInterfaceStyle == .dark, let capabilities, capabilities.versionMajor >= 25 {
            urlString += "/dark"
        }
        guard let url = URL(string: urlString) else { return }
        let downloader: SDWebImageDownloader
        if let existing = avatarDownloader {
            downloader = existing
        } else {
            downloader = SDWebImageDownloader(config: SDWebImageDownloader.shared.config)
            downloader.setValue(NCAppBranding.userAgent(), forHTTPHeaderField: "User-Agent")
            avatarDownloader = downloader
        }
        let requestID = avatarRequestID
        // The existing certificate operation and authentication modifier are retained.
        // NSURLCache retains the server's cache lifetime AND the custom-avatar header.
        avatarDownload = downloader.downloadImage(with: url, options: [.useNSURLCache], context: [.downloadRequestModifier: modifier], progress: nil) { [weak self] image, _, error, finished in
            guard finished else { return }
            DispatchQueue.main.async {
                guard let self, self.avatarRequestID == requestID, error == nil else { return }
                self.applyUserAvatar(image, response: self.avatarDownload?.response as? HTTPURLResponse)
            }
        }
    }

    func applyUserAvatar(_ image: UIImage?, response: HTTPURLResponse?) {
        // Only explicit server metadata permits replacing a downloaded image.
        // Missing metadata remains conservative, preserving possible profile photos.
        let isGenerated = response?.value(forHTTPHeaderField: "X-NC-IsCustomAvatar") == "0"
        self.image = isGenerated ? nil : image
        contentMode = .scaleAspectFill
        backgroundColor = RimaCallAppearance.avatarColor
    }

    override var image: UIImage? {
        didSet { updateInitialsVisibility() }
    }

    private func updateInitialsVisibility() {
        let placeholder = UIImage(named: "user-avatar", in: nil, compatibleWith: traitCollection)
        let defaultAvatar = image == nil || image?.isEqual(placeholder) == true ||
            (image?.imageAsset != nil && image?.imageAsset === placeholder?.imageAsset)
        initialsLabel.isHidden = !defaultAvatar
    }

    // Keep square physical bounds for both photo assets and native initials.
    override var alignmentRectInsets: UIEdgeInsets { .zero }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        layer.masksToBounds = true
        initialsLabel.font = .systemFont(ofSize: max(16, bounds.width * 0.34), weight: .semibold)
    }
}
