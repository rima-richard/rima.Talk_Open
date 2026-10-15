//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import LinkPresentation
import UIKit

///
/// Shares the original file, waiting for it if it is not downloaded yet.
///
/// The share sheet opens right away and builds its activity list from the placeholder. Only once
/// the user picked a destination does UIKit ask for `item`, on a background thread, and shows its
/// own progress while we wait. That way the download runs while the user is still choosing.
///
class MediaShareItemProvider: UIActivityItemProvider {

    private let placeholderURL: URL
    private let thumbnail: UIImage?
    private let requestFile: (@escaping (URL?) -> Void) -> Void
    private let timeout: TimeInterval
    private let stateLock = NSLock()
    private var failed = false

    var didFail: Bool {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        return self.failed
    }

    private func fail() -> NSNull {
        self.stateLock.lock()
        self.failed = !self.isCancelled
        self.stateLock.unlock()
        return NSNull()
    }

    init(placeholderURL: URL, thumbnail: UIImage?, timeout: TimeInterval = 60, requestFile: @escaping (@escaping (URL?) -> Void) -> Void) {
        self.placeholderURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString).appendingPathComponent(placeholderURL.lastPathComponent)
        self.timeout = timeout
        self.thumbnail = thumbnail
        self.requestFile = requestFile

        super.init(placeholderItem: self.placeholderURL)
    }

    ///
    /// The share sheet builds its header once, when it opens, and the file may not be downloaded at
    /// that point. So the picture the media viewer is showing is handed over instead.
    ///
    override func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = self.placeholderURL.lastPathComponent

        if let thumbnail = self.scaledThumbnail() {
            metadata.imageProvider = NSItemProvider(object: thumbnail)
        }

        return metadata
    }

    // The header is small and the image is handed to another process, so don't send a full sized one
    private func scaledThumbnail() -> UIImage? {
        guard let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 else { return nil }

        let scale = min(512 / thumbnail.size.width, 512 / thumbnail.size.height, 1)

        guard scale < 1 else { return thumbnail }

        return thumbnail.preparingThumbnail(of: .init(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale))
    }

    override var item: Any {
        // UIKit calls this on a background thread. Waiting below would deadlock otherwise.
        guard !Thread.isMainThread, !self.isCancelled else { return self.fail() }

        var resolvedURL: URL?
        let resultLock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            self.requestFile { fileURL in
                resultLock.lock()
                resolvedURL = fileURL
                resultLock.unlock()
                semaphore.signal()
            }
        }

        // Poll instead of waiting in one go, so dismissing the share sheet does not keep this
        // thread around until the timeout
        let deadline = Date().addingTimeInterval(self.timeout)

        while !self.isCancelled, Date() < deadline {
            if semaphore.wait(timeout: .now() + 0.1) == .success {
                break
            }
        }

        resultLock.lock()
        let result = resolvedURL
        resultLock.unlock()

        // A failed, timed-out or cancelled activity must never receive a cache guess.
        guard !self.isCancelled, Date() < deadline, let result,
              result.isFileURL, FileManager.default.fileExists(atPath: result.path) else { return self.fail() }

        return result
    }
}
