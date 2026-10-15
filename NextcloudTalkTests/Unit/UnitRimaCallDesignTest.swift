//
// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import WebRTC
import AVFoundation
@testable import NextcloudTalk

final class UnitRimaCallDesignTest: TestBaseRealm {

    private func drainMainQueue() {
        let updated = expectation(description: "UI updated")
        DispatchQueue.main.async { updated.fulfill() }
        wait(for: [updated], timeout: 2)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func withCallView(audioOnly: Bool = false, _ check: (CallViewController, UIWindow) throws -> Void) throws {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let room = NCRoom()
        room.accountId = account.accountId
        room.token = "rima-call-design-test"
        room.name = "rima-design-colleague"
        room.displayName = "Anna Beispiel"
        room.type = .oneToOne
        let controller = CallViewController(for: room, withAccount: account, audioOnly: audioOnly)
        controller.videoDisabledAtStart = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        drainMainQueue()
        controller.view.layoutIfNeeded()
        defer {
            controller.invalidateDetailedViewTimer()
            controller.viewWillDisappear(false)
            window.isHidden = true
            window.rootViewController = nil
        }
        try check(controller, window)
    }

    func testWaitingContentFitsSmallLandscapeAndLargeTypeWithoutTruncation() {
        XCTAssertEqual(RimaCallAvatarImageView.initials(for: "Anna Beispiel"), "AB")
        XCTAssertEqual(RimaCallAvatarImageView.initials(for: "Richard · Talk-Test"), "RT")
        XCTAssertEqual(RimaCallAvatarImageView.initials(for: "Änne Öztürk"), "ÄÖ")
        let incompleteRoom = NCRoom()
        incompleteRoom.accountId = TestBaseRealm.fakeAccountId
        incompleteRoom.token = "pending-contact"
        incompleteRoom.type = .oneToOne
        let pendingView = RimaCallWaitingView(frame: .zero)
        pendingView.configure(for: incompleteRoom)
        let initial = descendants(of: pendingView.avatarImageView).compactMap { $0 as? UILabel }.first
        XCTAssertFalse(initial?.isHidden ?? true)
        for size in [CGSize(width: 320, height: 488), CGSize(width: 393, height: 650), CGSize(width: 812, height: 220), CGSize(width: 1024, height: 600)] {
            for largeType in [false, true] {
                let view = RimaCallWaitingView(frame: CGRect(origin: .zero, size: size))
                view.nameLabel.text = "Alexandra Beispiel mit einem längeren Namen"
                view.statusLabel.text = "Warte, bis andere dem Anruf beitreten …"
                if largeType {
                    let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
                    view.nameLabel.font = UIFont.preferredFont(forTextStyle: .title1, compatibleWith: traits)
                    view.statusLabel.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
                }
                view.setNeedsLayout()
                view.layoutIfNeeded()
                for label in [view.nameLabel, view.statusLabel] {
                    XCTAssertGreaterThan(label.bounds.width, 0)
                    let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                    XCTAssertLessThanOrEqual(needed.height, label.bounds.height + 1)
                    let rect = label.convert(label.bounds, to: view)
                    XCTAssertGreaterThanOrEqual(rect.minX, 23)
                    XCTAssertLessThanOrEqual(rect.maxX, size.width - 23)
                }
                XCTAssertEqual(view.avatarImageView.bounds.width, view.avatarImageView.bounds.height, accuracy: 0.1)
                XCTAssertEqual(view.avatarImageView.layer.cornerRadius, view.avatarImageView.bounds.height / 2, accuracy: 0.1)
                XCTAssertFalse(view.hasAmbiguousLayout)
            }
        }
    }

    func testDownloadedGeneratedAvatarUsesNativeInitialsWhilePhotosRemainVisible() throws {
        let avatar = RimaCallAvatarImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        avatar.setFallbackDisplayName("Test · Talk-Test")
        let label = try XCTUnwrap(descendants(of: avatar).compactMap { $0 as? UILabel }.first)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { _ in
            UIColor.orange.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let url = try XCTUnwrap(URL(string: "https://example.invalid/avatar/test/512"))
        func response(_ value: String?) -> HTTPURLResponse? {
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: value.map { ["X-NC-IsCustomAvatar": $0] })
        }
        avatar.applyUserAvatar(image, response: response("0"))
        XCTAssertNil(avatar.image, "A downloaded generated avatar must not hide the native initials")
        XCTAssertEqual(label.text, "TT")
        XCTAssertFalse(label.isHidden)
        avatar.applyUserAvatar(image, response: response("1"))
        XCTAssertTrue(avatar.image === image)
        XCTAssertTrue(label.isHidden)
        XCTAssertEqual(avatar.contentMode, .scaleAspectFill)
        avatar.applyUserAvatar(image, response: response(nil))
        XCTAssertTrue(avatar.image === image, "Unknown metadata must preserve possible real photos")
        avatar.prepareForReuse()
        avatar.setFallbackDisplayName("Anna Beispiel")
        XCTAssertNil(avatar.image)
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(label.text, "AB")
    }

    func testVideoCallRemovesWaitingBackgroundAndKeepsCameraPreviewSeparate() throws {
        try withCallView { controller, _ in
            let collection = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
            XCTAssertTrue(collection.backgroundView === controller.waitingView)
            XCTAssertFalse(controller.localVideoViewWrapper.isDescendant(of: controller.waitingView))
            let previewParent = controller.localVideoViewWrapper.superview
            let previewFrame = controller.localVideoViewWrapper.frame
            controller.setCallState(.inCall)
            drainMainQueue()
            XCTAssertNil(collection.backgroundView, "No contact card may remain over active video")
            XCTAssertTrue(controller.localVideoViewWrapper.superview === previewParent)
            XCTAssertEqual(controller.localVideoViewWrapper.frame, previewFrame)
            controller.setCallState(.reconnecting)
            drainMainQueue()
            XCTAssertTrue(collection.backgroundView === controller.waitingView)
            XCTAssertEqual(controller.waitingView.statusLabel.text, NSLocalizedString("Connecting to the call …", comment: ""))
            controller.setCallState(.inCall)
            drainMainQueue()
            XCTAssertNil(collection.backgroundView)
        }
    }

    func testRoundControlsKeepTheirActionsAndReflectMutedDisabledStates() throws {
        try withCallView { controller, _ in
            let buttons = descendants(of: controller.view).compactMap { $0 as? UIButton }
            let microphone = try XCTUnwrap(buttons.first { $0.accessibilityLabel == NSLocalizedString("Microphone", comment: "") })
            let camera = try XCTUnwrap(buttons.first { $0.actions(forTarget: controller, forControlEvent: .touchUpInside)?.contains("videoButtonPressed:") == true })
            let speaker = try XCTUnwrap(buttons.first { $0.actions(forTarget: controller, forControlEvent: .touchUpInside)?.contains("speakerButtonPressed:") == true })
            for button in [microphone, camera, speaker] {
                XCTAssertEqual(button.bounds.width, 44, accuracy: 0.1)
                XCTAssertEqual(button.bounds.height, 44, accuracy: 0.1)
                XCTAssertEqual(button.layer.cornerRadius, 22, accuracy: 0.1)
            }
            XCTAssertTrue(microphone.actions(forTarget: controller, forControlEvent: .touchUpInside)?.contains("audioButtonPressed:") == true)
            XCTAssertFalse(microphone.gestureRecognizers?.compactMap { $0 as? UILongPressGestureRecognizer }.isEmpty ?? true)
            controller.setAudioMuteButtonActive(false)
            controller.setVideoDisableButtonActive(false)
            controller.setSpeakerButtonActive(true)
            drainMainQueue()
            XCTAssertTrue(microphone.isSelected)
            XCTAssertTrue(camera.isSelected)
            XCTAssertTrue(speaker.isSelected)
            controller.setVideoDisableButtonEnabled(false)
            drainMainQueue()
            XCTAssertFalse(camera.isEnabled)
            controller.setVideoDisableButtonEnabled(true)
            controller.setAudioMuteButtonActive(true)
            drainMainQueue()
            XCTAssertTrue(camera.isEnabled)
            XCTAssertFalse(microphone.isSelected)
        }
    }

    func testWideHangUpAndLeftControlsFitAudioAndVideoLayouts() throws {
        updateCapabilities { $0.setValue(["🎉"], forKey: "callReactions") }
        for audioOnly in [true, false] {
            try withCallView(audioOnly: audioOnly) { controller, window in
                let buttons = descendants(of: controller.view).compactMap { $0 as? UIButton }
                let microphone = try XCTUnwrap(buttons.first { $0.accessibilityLabel == NSLocalizedString("Microphone", comment: "") })
                let hangUp = try XCTUnwrap(buttons.first { $0.accessibilityLabel == NSLocalizedString("Hang up", comment: "") })
                let stack = try XCTUnwrap(microphone.superview as? UIStackView)
                let bar = try XCTUnwrap(stack.superview)
                for size in [CGSize(width: 320, height: 568), CGSize(width: 393, height: 852), CGSize(width: 430, height: 932), CGSize(width: 812, height: 375)] {
                    window.frame = CGRect(origin: .zero, size: size)
                    controller.view.frame = window.bounds
                    controller.view.setNeedsLayout()
                    controller.view.layoutIfNeeded()
                    controller.adjustBars()
                    drainMainQueue()
                    controller.view.layoutIfNeeded()
                    XCTAssertEqual(controller.view.bounds.size, size)
                    let barFrame = bar.convert(bar.bounds, to: controller.view)
                    XCTAssertGreaterThanOrEqual(barFrame.minX, 0)
                    XCTAssertLessThanOrEqual(barFrame.maxX, size.width)
                    XCTAssertEqual(stack.frame.minX, 8, accuracy: 0.1)
                    XCTAssertGreaterThanOrEqual(hangUp.bounds.width, 88)
                    XCTAssertEqual(hangUp.bounds.height, 48, accuracy: 0.1)
                    XCTAssertEqual(hangUp.layer.cornerRadius, 24, accuracy: 0.1)
                    XCTAssertLessThanOrEqual(stack.frame.maxX + 12, hangUp.frame.minX + 0.5)
                    XCTAssertEqual(hangUp.frame.maxX, bar.bounds.width - 8, accuracy: 0.1)
                    XCTAssertTrue(hangUp.actions(forTarget: controller, forControlEvent: .touchUpInside)?.contains("hangupButtonPressed:") == true)
                    for button in stack.arrangedSubviews where !button.isHidden {
                        XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
                        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
                    }
                }
            }
        }
    }

    func testParticipantPortraitDoesNotChangeVideoGeometryOrVisibility() throws {
        let cell = try XCTUnwrap(UINib(nibName: kCallParticipantCellNibName, bundle: Bundle(for: CallParticipantViewCell.self)).instantiate(withOwner: nil).first as? CallParticipantViewCell)
        cell.frame = CGRect(x: 0, y: 0, width: 393, height: 650)
        cell.layoutIfNeeded()
        XCTAssertEqual(cell.peerAvatarImageView.bounds.width, 200, accuracy: 1)
        let renderer = RTCMTLVideoView(frame: .zero)
        cell.setVideoView(renderer)
        cell.setRemoteVideoSize(CGSize(width: 640, height: 480))
        drainMainQueue()
        cell.videoDisabled = false
        let videoFrame = renderer.frame
        XCTAssertFalse(renderer.isHidden)
        XCTAssertTrue(cell.peerAvatarImageView.isHidden)
        XCTAssertLessThanOrEqual(videoFrame.minX, 0)
        XCTAssertLessThanOrEqual(videoFrame.minY, 0)
        XCTAssertGreaterThanOrEqual(videoFrame.maxX, cell.bounds.width)
        XCTAssertGreaterThanOrEqual(videoFrame.maxY, cell.bounds.height)
        XCTAssertEqual(videoFrame.width / videoFrame.height, 640.0 / 480.0, accuracy: 0.001)
        cell.videoDisabled = true
        XCTAssertTrue(renderer.isHidden)
        XCTAssertFalse(cell.peerAvatarImageView.isHidden)
        XCTAssertEqual(renderer.frame, videoFrame)
        cell.videoDisabled = false
        XCTAssertFalse(renderer.isHidden)
        XCTAssertEqual(renderer.frame, videoFrame)
        for size in [CGSize(width: 128, height: 128), CGSize(width: 200, height: 150), CGSize(width: 650, height: 300)] {
            cell.frame.size = size
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            XCTAssertLessThanOrEqual(cell.peerAvatarImageView.frame.maxY, size.height - 21)
            XCTAssertGreaterThanOrEqual(cell.peerAvatarImageView.frame.minY, 21)
        }
    }

    func testCallKitIconIsBrandedAndHasTransparentCorners() throws {
        let data = try XCTUnwrap(RimaCallBranding.callKitIconData())
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 120)
        var pixels = [UInt8](repeating: 0, count: 120 * 120 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 480, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 120, height: 120))
            return true
        }
        XCTAssertTrue(rendered)
        XCTAssertEqual(pixels[3], 0, "An opaque app-icon square is not a valid CallKit template")
        XCTAssertEqual(pixels[(119 * 120 + 119) * 4 + 3], 0)
        XCTAssertGreaterThan(pixels[(60 * 120 + 60) * 4 + 3], 240)
    }

    func testMissedVideoCallsAreDistinctAndUnknownCallsStayGeneric() {
        let video = NCNotificationController.missedCallBody(displayName: "Anna Beispiel", hasVideo: true)
        let generic = NCNotificationController.missedCallBody(displayName: "Anna Beispiel", hasVideo: false)
        XCTAssertTrue(video.hasPrefix("📹 "))
        XCTAssertTrue(video.contains("Anna Beispiel"))
        XCTAssertTrue(generic.hasPrefix("☎️ "))
        XCTAssertNotEqual(video, generic)
    }

    func testNativeRimaCallPreview() throws {
        try withCallView(audioOnly: true) { controller, window in
            controller.waitingView.statusLabel.text = "Warte auf Antwort …"
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                window.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Rima-Anruf-Monochrom"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testHDMigrationRunsOnceAndPreservesLaterManualChoice() throws {
        let name = "RimaHDDefaultsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var storedResolution = "640x480"
        var stores = 0
        let store: (String) -> Bool = { storedResolution = $0; stores += 1; return true }
        RimaVideoDefaults.apply(defaults: defaults, store: store)
        XCTAssertEqual(storedResolution, "1280x720")
        XCTAssertTrue(defaults.bool(forKey: RimaVideoDefaults.migrationKey))
        storedResolution = "480x360"
        RimaVideoDefaults.apply(defaults: defaults, store: store)
        XCTAssertEqual(storedResolution, "480x360")
        XCTAssertEqual(stores, 1)
    }

    func testHDMigrationDoesNotMarkFailedStoreAsComplete() throws {
        let name = "RimaHDDefaultsRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        RimaVideoDefaults.apply(defaults: defaults) { _ in false }
        XCTAssertFalse(defaults.bool(forKey: RimaVideoDefaults.migrationKey))
        RimaVideoDefaults.apply(defaults: defaults) { $0 == "1280x720" }
        XCTAssertTrue(defaults.bool(forKey: RimaVideoDefaults.migrationKey))
    }

    func testFreshVideoSettingsDefaultToHDWithoutChangingCodecOrBitrate() {
        let defaults = UserDefaults.standard
        let key = "rtc_video_resolution_key"
        let previous = defaults.object(forKey: key)
        let codec = defaults.object(forKey: "rtc_video_codec_key") as? NSObject
        let bitrate = defaults.object(forKey: "rtc_max_bitrate_key") as? NSObject
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        let model = ARDSettingsModel()
        XCTAssertEqual(model.currentVideoResolutionSettingFromStore(), "1280x720")
        XCTAssertEqual(model.currentVideoResolutionWidthFromStore(), 1280)
        XCTAssertEqual(model.currentVideoResolutionHeightFromStore(), 720)
        XCTAssertEqual(defaults.object(forKey: "rtc_video_codec_key") as? NSObject, codec)
        XCTAssertEqual(defaults.object(forKey: "rtc_max_bitrate_key") as? NSObject, bitrate)
    }

    func testRimaRingtoneSelectionPersistsAndInvalidChoiceFallsBack() throws {
        let name = "RimaCallToneTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(RimaCallTone.selected(in: defaults), .resonanz)
        defaults.set("missing-tone", forKey: RimaCallTone.preferenceKey)
        XCTAssertEqual(RimaCallTone.selected(in: defaults), .resonanz)
        RimaCallTone.bogen.store(in: defaults)
        XCTAssertEqual(RimaCallTone.selected(in: defaults), .bogen)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertEqual(RimaCallTone.selected(in: reopened), .bogen)
    }

    func testRimaCallSoundResourcesDecodeAndProgressPlayerStartsStopped() throws {
        for tone in RimaCallTone.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: tone.fileName, withExtension: nil))
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            XCTAssertEqual(file.processingFormat.channelCount, 1)
            XCTAssertGreaterThan(duration, 0)
            XCTAssertLessThan(duration, 30)
        }
        let player = try XCTUnwrap(RimaCallSounds.outgoingPlayer())
        XCTAssertEqual(player.duration, 5, accuracy: 0.01)
        XCTAssertEqual(player.numberOfLoops, -1)
        XCTAssertEqual(player.volume, 0.45, accuracy: 0.01)
        XCTAssertFalse(player.isPlaying, "Constructing the signal must not start playback or a call")
    }
}
