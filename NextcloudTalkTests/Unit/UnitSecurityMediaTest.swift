//
// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import NextcloudKit
import UIKit
@testable import NextcloudTalk

@MainActor
final class UnitSecurityMediaTest: XCTestCase {
    private var controllers: [NCChatFileController] = []
    private var temporaryFiles: [URL] = []

    override func tearDownWithError() throws {
        controllers.forEach { $0.cancelDownload(); $0.deleteDownloadDirectory() }
        temporaryFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        try super.tearDownWithError()
    }

    private func account() -> TalkAccount {
        let account = TalkAccount()
        account.accountId = "media-security-\(UUID().uuidString)"
        account.userId = "synthetic-user"
        account.server = "https://media.invalid"
        return account
    }

    private func metadata(id: String, etag: String = "revision-1", name: String = "same.jpg") -> NKFile {
        let file = NKFile()
        file.fileId = id
        file.fileName = name
        file.path = "/remote.php/dav/files/synthetic-user/photos/"
        file.etag = etag
        file.date = Date(timeIntervalSince1970: 1_700_000_000) as NSDate
        file.size = 4
        return file
    }

    private func controller(account: TalkAccount, metadata: @escaping NCChatFileController.MetadataLoader,
                            download: @escaping NCChatFileController.FileLoader) -> NCChatFileController {
        let controller = NCChatFileController(account: account, metadataLoader: metadata, fileLoader: download)
        controllers.append(controller)
        return controller
    }

    private func download(_ controller: NCChatFileController, id: String) throws -> URL {
        var result: Result<NCChatFileStatus, ChatFileDownloadError>?
        controller.downloadFile(withFileId: id) { result = $0 }
        return URL(fileURLWithPath: try XCTUnwrap(result).get().fileLocalPath!)
    }

    func testSameNameFilesAndRevisionsNeverReuseEachOthersBytes() throws {
        let account = account()
        var revision = "old"
        var requestCount = 0
        let controller = controller(account: account, metadata: { _, id, completion in
            completion(self.metadata(id: id, etag: revision), nil)
        }, download: { _, _, path, etag, _, _, completion in
            requestCount += 1
            try! Data((etag == "old" ? "AAAA" : "BBBB").utf8).write(to: URL(fileURLWithPath: path))
            completion(etag, nil)
        })

        let first = try download(controller, id: "1")
        let second = try download(controller, id: "2")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try download(controller, id: "1"), first)
        XCTAssertEqual(requestCount, 2, "The validated same resource should still use its cache")
        revision = "new"
        let replaced = try download(controller, id: "1")
        XCTAssertNotEqual(first, replaced)
        XCTAssertEqual(try Data(contentsOf: first), Data("AAAA".utf8))
        XCTAssertEqual(try Data(contentsOf: replaced), Data("BBBB".utf8))
        XCTAssertEqual(replaced.lastPathComponent, "same.jpg")
    }

    func testLegacyBasenameAndOtherAccountsAreNotCacheHits() throws {
        let firstAccount = account()
        let legacyDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("download")
            .appendingPathComponent(firstAccount.accountId)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        temporaryFiles.append(legacyDirectory)
        try Data("LEAK".utf8).write(to: legacyDirectory.appendingPathComponent("same.jpg"))
        var requests = 0
        func make(_ account: TalkAccount) -> NCChatFileController {
            controller(account: account, metadata: { _, id, completion in
                completion(self.metadata(id: id), nil)
            }, download: { _, _, path, etag, _, _, completion in
                requests += 1
                try! Data("SAFE".utf8).write(to: URL(fileURLWithPath: path))
                completion(etag, nil)
            })
        }
        let first = try download(make(firstAccount), id: "1")
        let second = try download(make(account()), id: "1")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(try Data(contentsOf: first), Data("SAFE".utf8))
    }

    private func legacyDirectory(for account: TalkAccount) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("download")
            .appendingPathComponent(account.accountId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)
    }

    func testLegacyFilesRemainAccountedForAndRemovedByClearAndLogout() throws {
        let first = account(), other = account()
        let controller = controller(account: first, metadata: { _, _, _ in XCTFail("No network needed") },
                                    download: { _, _, _, _, _, _, _ in XCTFail("No network needed") })
        let legacy = legacyDirectory(for: first), unrelated = legacyDirectory(for: other)
        temporaryFiles += [legacy, unrelated]
        for directory in [legacy, unrelated] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("OLD!".utf8).write(to: directory.appendingPathComponent("legacy.jpg"))
        }
        let current = URL(fileURLWithPath: controller.tempDirectoryPath).appendingPathComponent("current.jpg")
        try Data("NEW!".utf8).write(to: current)
        XCTAssertEqual(controller.getDiskUsage(), 8)
        controller.clearDownloadDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: controller.tempDirectoryPath))
        XCTAssertEqual(controller.getDiskUsage(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.appendingPathComponent("legacy.jpg").path))

        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("OLD!".utf8).write(to: legacy.appendingPathComponent("legacy.jpg"))
        try Data("NEW!".utf8).write(to: current)
        controller.deleteDownloadDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "Logout must remove old account data too")
        XCTAssertFalse(FileManager.default.fileExists(atPath: controller.tempDirectoryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testAgedCleanupKeepsFreshRevisionInsideOldDirectoryAndRemovesOldLegacyFiles() throws {
        let account = account()
        let controller = controller(account: account, metadata: { _, _, _ in XCTFail("No network needed") },
                                    download: { _, _, _, _, _, _, _ in XCTFail("No network needed") })
        let oldParent = URL(fileURLWithPath: controller.tempDirectoryPath).appendingPathComponent("file-id")
        let freshChild = oldParent.appendingPathComponent("new-revision/photo.jpg")
        let oldChild = oldParent.appendingPathComponent("old.jpg")
        let legacy = legacyDirectory(for: account)
        temporaryFiles.append(legacy)
        try FileManager.default.createDirectory(at: freshChild.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let oldLegacy = legacy.appendingPathComponent("old.jpg")
        for url in [freshChild, oldChild, oldLegacy] { try Data("DATA".utf8).write(to: url) }
        let oldDate = Date(timeIntervalSinceNow: -14 * 24 * 60 * 60)
        for url in [oldParent, oldChild, oldLegacy] {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
            try FileManager.default.setAttributes([.creationDate: oldDate], ofItemAtPath: url.path)
        }
        controller.removeOldFilesFromCache()
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshChild.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldChild.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLegacy.path))
        XCTAssertEqual(controller.getDiskUsage(), 4)
    }

    func testMissingValidatedViewerOriginalRetriesAndReportsFailureImmediately() throws {
        let account = account()
        let imageData = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }.pngData())
        var unavailable = false
        var metadataRequests = 0
        let controller = controller(account: account, metadata: { _, id, completion in
            metadataRequests += 1
            if unavailable {
                completion(nil, "Synthetic unavailable file")
            } else {
                let file = self.metadata(id: id, name: "photo.png")
                file.size = Int64(imageData.count)
                completion(file, nil)
            }
        }, download: { _, _, path, etag, _, _, completion in
            try! imageData.write(to: URL(fileURLWithPath: path))
            completion(etag, nil)
        })
        let message = NCChatMessage()
        message.messageParametersJSONString = """
        {"file":{"type":"file","id":"1","name":"photo.png","path":"photos/photo.png","mimetype":"image/png","preview-available":"no"}}
        """
        let viewer = NCMediaViewerPageViewController(message: message, account: account, fileDownloader: controller)
        viewer.loadViewIfNeeded()
        var original: URL?
        viewer.requestSharableFile { original = $0 }
        let decoded = expectation(for: NSPredicate { _, _ in viewer.sharableFileURL != nil }, evaluatedWith: nil)
        wait(for: [decoded], timeout: 2)
        try FileManager.default.removeItem(at: XCTUnwrap(original))
        unavailable = true
        var completed = false
        viewer.requestSharableFile { result in
            XCTAssertNil(result)
            completed = true
        }
        XCTAssertTrue(completed, "A missing original must retry instead of waiting for the share timeout")
        XCTAssertEqual(metadataRequests, 2)
        XCTAssertNil(viewer.sharableFileURL)
    }

    func testFailedPartialDownloadNeverBecomesAReusableOriginal() throws {
        var fail = true
        var stagingPath = ""
        var requests = 0
        let controller = controller(account: account(), metadata: { _, id, completion in
            completion(self.metadata(id: id), nil)
        }, download: { _, _, path, etag, _, _, completion in
            requests += 1
            stagingPath = path
            try! Data("PART".utf8).write(to: URL(fileURLWithPath: path))
            completion(etag, fail ? "Synthetic download failure" : nil)
        })
        XCTAssertThrowsError(try download(controller, id: "1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingPath))
        fail = false
        XCTAssertEqual(try Data(contentsOf: download(controller, id: "1")), Data("PART".utf8))
        XCTAssertEqual(requests, 2)
    }

    func testWrongMetadataAndChangedDownloadRevisionAreRejected() {
        let wrong = controller(account: account(), metadata: { _, _, completion in
            completion(self.metadata(id: "different"), nil)
        }, download: { _, _, _, _, _, _, _ in XCTFail("Wrong file ID must not download") })
        XCTAssertThrowsError(try download(wrong, id: "1"))
        let changed = controller(account: account(), metadata: { _, id, completion in
            completion(self.metadata(id: id), nil)
        }, download: { _, _, path, _, _, _, completion in
            try! Data("DATA".utf8).write(to: URL(fileURLWithPath: path))
            completion("different-etag", nil)
        })
        XCTAssertThrowsError(try download(changed, id: "1"))
    }

    func testCancelledAttemptCannotCompleteItsReplacement() throws {
        var pending: [(NKFile?, String?) -> Void] = []
        var cancellations = 0
        var successes = 0
        let controller = controller(account: account(), metadata: { _, _, completion in pending.append(completion) },
                                    download: { _, _, path, etag, _, _, completion in
            try! Data("SAFE".utf8).write(to: URL(fileURLWithPath: path))
            completion(etag, nil)
        })
        controller.downloadFile(withFileId: "old") { result in
            if case .failure(.cancelled) = result { cancellations += 1 } else { XCTFail() }
        }
        controller.downloadFile(withFileId: "new") { result in
            if case .success(let status) = result {
                XCTAssertEqual(status.fileId, "new")
                successes += 1
            } else { XCTFail() }
        }
        pending[0](metadata(id: "old"), nil)
        XCTAssertEqual(successes, 0)
        pending[1](metadata(id: "new"), nil)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(successes, 1)
    }

    func testLateDownloadCompletionCannotPublishCancelledBytesOrFinishNewAttempt() throws {
        var completions: [(String?, String?) -> Void] = []
        var staged: [URL] = []
        var cancellations = 0
        var successes = 0
        let controller = controller(account: account(), metadata: { _, id, completion in
            completion(self.metadata(id: id), nil)
        }, download: { _, _, path, _, cancellation, _, completion in
            staged.append(URL(fileURLWithPath: path))
            cancellation { }
            completions.append(completion)
        })
        controller.downloadFile(withFileId: "old") { result in
            if case .failure(.cancelled) = result { cancellations += 1 } else { XCTFail() }
        }
        controller.downloadFile(withFileId: "new") { result in
            if case .success(let status) = result {
                XCTAssertEqual(status.fileId, "new")
                successes += 1
            } else { XCTFail() }
        }
        try Data("LATE".utf8).write(to: staged[0])
        completions[0]("revision-1", nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged[0].path))
        XCTAssertEqual(successes, 0)
        try Data("SAFE".utf8).write(to: staged[1])
        completions[1]("revision-1", nil)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(successes, 1)
    }

    func testSharedDownloaderSeparatesAccountsButCoalescesSameResource() {
        let first = account(), second = account()
        var pending: [String: (NKFile?, String?) -> Void] = [:]
        let shared = ChatFileDownloader(makeController: { account in
            self.controller(account: account, metadata: { account, _, completion in pending[account.accountId] = completion },
                            download: { _, _, path, etag, _, _, completion in
                try! Data("SAFE".utf8).write(to: URL(fileURLWithPath: path))
                completion(etag, nil)
            })
        })
        let finished = expectation(description: "Each account receives only its own file")
        finished.expectedFulfillmentCount = 3
        for account in [first, first, second] {
            shared.downloadFile(withFileId: "1", fromAccount: account) { result in
                XCTAssertEqual(try? result.get().accountId, account.accountId)
                finished.fulfill()
            }
        }
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(shared.downloadStatus(forFileId: "1", accountId: second.accountId)?.accountId, second.accountId)
        pending[first.accountId]?(metadata(id: "1"), nil)
        pending[second.accountId]?(metadata(id: "1"), nil)
        wait(for: [finished], timeout: 2)
    }

    private func item(from provider: MediaShareItemProvider) -> Any {
        let finished = expectation(description: "Share item resolved")
        var result: Any = NSNull()
        DispatchQueue.global().async {
            result = provider.item
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        return result
    }

    private func existingUnrelatedFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).jpg")
        try Data("UNRELATED".utf8).write(to: url)
        temporaryFiles.append(url)
        return url
    }

    func testShareFailureTimeoutAndCancellationDoNotReturnExistingPlaceholderFile() throws {
        let unrelated = try existingUnrelatedFile()
        let failed = MediaShareItemProvider(placeholderURL: unrelated, thumbnail: nil) { $0(nil) }
        XCTAssertTrue(item(from: failed) is NSNull)
        XCTAssertTrue(failed.didFail)
        let timeout = MediaShareItemProvider(placeholderURL: unrelated, thumbnail: nil, timeout: 0.05) { _ in }
        XCTAssertTrue(item(from: timeout) is NSNull)
        XCTAssertTrue(timeout.didFail)
        let cancelled = MediaShareItemProvider(placeholderURL: unrelated, thumbnail: nil) { $0(unrelated) }
        cancelled.cancel()
        XCTAssertTrue(item(from: cancelled) is NSNull)
        XCTAssertFalse(cancelled.didFail)
        XCTAssertTrue(failed.item is NSNull, "A main-thread request cannot return a guessed cache path")
    }

    func testSuccessfulShareReturnsOnlyTheResolvedFile() throws {
        let unrelated = try existingUnrelatedFile()
        let original = try existingUnrelatedFile()
        let provider = MediaShareItemProvider(placeholderURL: unrelated, thumbnail: nil) { $0(original) }
        XCTAssertEqual(item(from: provider) as? URL, original)
        XCTAssertFalse(provider.didFail)
    }
}
