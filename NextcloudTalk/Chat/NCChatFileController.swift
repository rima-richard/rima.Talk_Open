//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CryptoKit
import NextcloudKit

public extension NSNotification.Name {
    static let NCChatFileControllerDidChangeIsDownloading = NSNotification.Name("NCChatFileControllerDidChangeIsDownloadingNotification")
    static let NCChatFileControllerDidChangeDownloadProgress = NSNotification.Name("NCChatFileControllerDidChangeDownloadProgressNotification")
}

public class NCChatFileController: NSObject {

    /// Called exactly once with the downloaded file, or with the reason why it could not be downloaded.
    public typealias CompletionHandler = (Result<NCChatFileStatus, ChatFileDownloadError>) -> Void

    public private(set) var tempDirectoryPath = ""

    private let account: TalkAccount
    private let deleteFilesOlderThanDays = 7
    private(set) var fileStatus: NCChatFileStatus?
    private var cancelDownloadHandler: (() -> Void)?
    private var completionHandler: CompletionHandler?
    private var activeAttempt: UUID?
    private let metadataLoader: MetadataLoader
    private let fileLoader: FileLoader

    typealias MetadataLoader = (TalkAccount, String, @escaping (NKFile?, String?) -> Void) -> Void
    typealias FileLoader = (TalkAccount, String, String, String, @escaping (@escaping () -> Void) -> Void,
                           @escaping (Progress) -> Void, @escaping (String?, String?) -> Void) -> Void

    init(account: TalkAccount, metadataLoader: @escaping MetadataLoader = NCChatFileController.loadMetadata,
         fileLoader: @escaping FileLoader = NCChatFileController.loadFile) {
        self.account = account
        self.metadataLoader = metadataLoader
        self.fileLoader = fileLoader

        super.init()

        self.initDownloadDirectory()
        AllocationTracker.shared.addAllocation()
    }

    deinit {
        AllocationTracker.shared.removeAllocation()
    }

    private func initDownloadDirectory() {
        // A separate namespace deliberately excludes the old basename-only cache.
        let encodedAccountId = Self.cacheComponent(self.account.accountId)
        let fileManager = FileManager.default

        tempDirectoryPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("download-v2")
        tempDirectoryPath = (tempDirectoryPath as NSString).appendingPathComponent(encodedAccountId)

        print("Directory for downloads: \(tempDirectoryPath)")

        if !fileManager.fileExists(atPath: tempDirectoryPath) {
            // Make sure our download directory exists
            try? fileManager.createDirectory(atPath: tempDirectoryPath, withIntermediateDirectories: true)
        }
    }

    // Legacy files are counted and removed for their account, but never used as verified originals.
    private var managedCacheDirectories: [String] {
        var directories = [self.tempDirectoryPath]
        if let component = self.account.accountId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
           !component.isEmpty, component != ".", component != "..",
           (component as NSString).lastPathComponent == component {
            let legacyRoot = (NSTemporaryDirectory() as NSString).appendingPathComponent("download")
            directories.append((legacyRoot as NSString).appendingPathComponent(component))
        }
        return directories
    }

    public func removeOldFilesFromCache() {
        let fileManager = FileManager.default
        guard let thresholdDate = Calendar.current.date(byAdding: .day, value: -deleteFilesOlderThanDays, to: Date()) else { return }

        for directory in self.managedCacheDirectories {
            guard let enumerator = fileManager.enumerator(atPath: directory) else { continue }
            for case let file as String in enumerator {
                let filePath = (directory as NSString).appendingPathComponent(file)
                guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let creationDate = attributes[.creationDate] as? Date,
                      creationDate < thresholdDate else { continue }

                // A file-ID/revision directory can be old while containing a fresh download.
                try? fileManager.removeItem(atPath: filePath)
            }
        }
    }

    public func deleteDownloadDirectory() {
        for directory in self.managedCacheDirectories {
            try? FileManager.default.removeItem(atPath: directory)
        }
    }

    public func clearDownloadDirectory() {
        deleteDownloadDirectory()
        initDownloadDirectory()
    }

    public func getDiskUsage() -> Int {
        let fileManager = FileManager.default
        var folderSize = 0
        for directory in self.managedCacheDirectories {
            guard let enumerator = fileManager.enumerator(atPath: directory) else { continue }
            for case let file as String in enumerator {
                let filePath = (directory as NSString).appendingPathComponent(file)
                guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                      attributes[.type] as? FileAttributeType == .typeRegular else { continue }
                folderSize += (attributes[.size] as? Int) ?? 0
            }
        }
        return folderSize
    }

    private func isFileInCache(_ filePath: String, withModificationDate date: Date, withSize size: Int64) -> Bool {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: filePath) else { return false }

        let fileAttributes = try? fileManager.attributesOfItem(atPath: filePath)
        let modificationDate = fileAttributes?[.modificationDate] as? Date
        let fileType = fileAttributes?[.type] as? FileAttributeType
        let fileSize = (fileAttributes?[.size] as? Int64) ?? 0

        if fileType == .typeRegular, let modificationDate, date.compare(modificationDate) == .orderedSame, fileSize == size {
            return true
        }

        // At this point there's a file in our cache but there's a different one on the server
        print("Deleting file from cache: \(filePath)")
        try? fileManager.removeItem(atPath: filePath)

        return false
    }

    private func setDate(onFile filePath: String, withCreationDate creationDate: Date?, withModificationDate modificationDate: Date?) {
        // Setting both, modification- and creationDate in one go does not work, we will end up with the modification date in both fields
        // Also the creationDate needs to be set after modificationDate (most likely because creation cannot be later than modification in theory)
        if let modificationDate {
            try? FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: filePath)
        }

        if let creationDate {
            try? FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: filePath)
        }
    }

    public func moveFileToTemporaryDirectory(fromSourcePath sourcePath: String, destinationPath: String) -> Bool {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationPath) {
            print("File is already in temporary directory: \(destinationPath)")
            return false
        }

        do {
            try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
            print("File successfully moved to: \(destinationPath)")
            return true
        } catch {
            print("Error while moving file to temporary directory: \(error.localizedDescription)")
            return false
        }
    }

    private static func cacheComponent(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cachedURL(for file: NKFile, fileId: String) -> URL {
        let revision = "\(file.etag)\n\(file.date.timeIntervalSince1970)\n\(file.size)"
        return URL(fileURLWithPath: self.tempDirectoryPath, isDirectory: true)
            .appendingPathComponent(Self.cacheComponent(fileId), isDirectory: true)
            .appendingPathComponent(Self.cacheComponent(revision), isDirectory: true)
            .appendingPathComponent(file.fileName)
    }

    private static func loadMetadata(account: TalkAccount, fileId: String, completion: @escaping (NKFile?, String?) -> Void) {
        NCAPIController.sharedInstance().getFileById(forAccount: account, withFileId: fileId) { file, error in
            completion(file, error?.errorCode == 0 ? nil : error?.errorDescription)
        }
    }

    private static func loadFile(account: TalkAccount, remotePath: String, localPath: String, etag: String,
                                 cancellation: @escaping (@escaping () -> Void) -> Void,
                                 progress: @escaping (Progress) -> Void, completion: @escaping (String?, String?) -> Void) {
        // Another account's metadata lookup can have changed NextcloudKit's shared credentials.
        guard NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId) != nil,
              NCKeyChainController.sharedInstance().token(forAccountId: account.accountId) != nil else {
            completion(nil, "Account is no longer available")
            return
        }
        NCAPIController.sharedInstance().setupNCCommunication(forAccount: account)
        let headers = etag.isEmpty ? nil : ["If-Match": "\"\(etag.replacingOccurrences(of: "\"", with: ""))\""]
        NextcloudKit.shared.download(serverUrlFileName: remotePath, fileNameLocalPath: localPath,
                                    addCustomHeaders: headers, queue: .main, taskHandler: { task in
            cancellation { task.cancel() }
        }, progressHandler: { value in
            progress(value)
        }, completionHandler: { _, responseETag, _, _, _, error in
            completion(responseETag, error.errorCode == 0 ? nil : error.errorDescription)
        })
    }

    // Stops only the current attempt. Late callbacks cannot finish or cancel a newer download.
    public func cancelDownload() {
        self.cancelDownloadHandler?()
        self.cancelDownloadHandler = nil
        self.finish(with: .failure(.cancelled))
    }

    public func downloadFile(withFileId fileId: String, completionHandler: @escaping CompletionHandler) {
        self.cancelDownload()
        let attempt = UUID()
        self.activeAttempt = attempt
        self.completionHandler = completionHandler

        let fileStatus = NCChatFileStatus(fileId: fileId, fileName: "", filePath: "", accountId: self.account.accountId)
        self.fileStatus = fileStatus
        self.didChangeIsDownloadingNotification(isDownloading: true)

        self.metadataLoader(self.account, fileId) { file, error in
            guard self.activeAttempt == attempt else { return }
            guard let file, error == nil, !file.directory, file.fileId == fileId,
                  !file.fileName.isEmpty, file.fileName != ".", file.fileName != "..",
                  (file.fileName as NSString).lastPathComponent == file.fileName, file.size >= 0 else {
                self.finish(with: .failure(.fileUnavailable(errorDescription: error ?? "Invalid file metadata")))
                return
            }

            let remoteDavPrefix = "/remote.php/dav/files/\(self.account.userId)/"
            let directoryPath = file.path.components(separatedBy: remoteDavPrefix).last ?? ""
            fileStatus.fileName = file.fileName
            fileStatus.filePath = "\(directoryPath)\(file.fileName)"

            let remotePath = "\(self.account.server)\(NCAPIController.sharedInstance().filesPath(forAccount: self.account))/\(fileStatus.filePath)"
            let localURL = self.cachedURL(for: file, fileId: fileId)
            fileStatus.fileLocalPath = localURL.path

            if self.isFileInCache(localURL.path, withModificationDate: file.date as Date, withSize: file.size) {
                self.finish(with: .success(fileStatus))
                return
            }

            let stagingURL = localURL.deletingLastPathComponent().appendingPathComponent(".\(attempt.uuidString).part")
            do {
                try FileManager.default.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            } catch {
                self.finish(with: .failure(.downloadFailed(errorDescription: error.localizedDescription)))
                return
            }

            self.fileLoader(self.account, remotePath, stagingURL.path, file.etag, { cancel in
                guard self.activeAttempt == attempt else {
                    cancel()
                    try? FileManager.default.removeItem(at: stagingURL)
                    return
                }
                self.cancelDownloadHandler = {
                    cancel()
                    try? FileManager.default.removeItem(at: stagingURL)
                }
            }, { progress in
                guard self.activeAttempt == attempt else { return }
                self.didChangeDownloadProgressNotification(progress: progress)
            }, { responseETag, error in
                defer { try? FileManager.default.removeItem(at: stagingURL) }
                guard self.activeAttempt == attempt else { return }
                self.cancelDownloadHandler = nil

                let attributes = try? FileManager.default.attributesOfItem(atPath: stagingURL.path)
                let downloadedSize = (attributes?[.size] as? NSNumber)?.int64Value
                let revisionMatches = responseETag == nil || file.etag.isEmpty ||
                    responseETag?.replacingOccurrences(of: "\"", with: "") == file.etag.replacingOccurrences(of: "\"", with: "")
                guard error == nil, downloadedSize == file.size, revisionMatches else {
                    self.finish(with: .failure(.downloadFailed(errorDescription: error ?? "File changed during download")))
                    return
                }

                do {
                    // Publish a complete file only; concurrent attempts for the same revision can reuse it.
                    if !self.isFileInCache(localURL.path, withModificationDate: file.date as Date, withSize: file.size) {
                        self.setDate(onFile: stagingURL.path, withCreationDate: Date(), withModificationDate: file.date as Date)
                        try FileManager.default.moveItem(at: stagingURL, to: localURL)
                    }
                    self.finish(with: .success(fileStatus))
                } catch {
                    self.finish(with: .failure(.downloadFailed(errorDescription: error.localizedDescription)))
                }
            })
        }
    }

    /// Reports the outcome of a download, making sure the completion handler runs only once.
    private func finish(with result: Result<NCChatFileStatus, ChatFileDownloadError>) {
        self.activeAttempt = nil
        if self.fileStatus?.isDownloading == true {
            self.didChangeIsDownloadingNotification(isDownloading: false)
        }

        let completionHandler = self.completionHandler
        self.completionHandler = nil

        completionHandler?(result)
    }

    private func didChangeIsDownloadingNotification(isDownloading: Bool) {
        guard let fileStatus else { return }

        fileStatus.isDownloading = isDownloading

        NotificationCenter.default.post(name: .NCChatFileControllerDidChangeIsDownloading, object: self, userInfo: ["fileStatus": fileStatus])
    }

    private func didChangeDownloadProgressNotification(progress: Progress) {
        guard let fileStatus else { return }

        fileStatus.downloadProgress = Float(progress.fractionCompleted)
        fileStatus.canReportProgress = progress.totalUnitCount != -1

        NotificationCenter.default.post(name: .NCChatFileControllerDidChangeDownloadProgress, object: self, userInfo: ["fileStatus": fileStatus])
    }
}
