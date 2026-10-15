//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class NCChatFileStatus: NSObject {

    public let accountId: String?
    public var fileId: String
    public var fileName: String
    public var filePath: String
    public var fileLocalPath: String?
    public var isDownloading: Bool = false
    public var canReportProgress: Bool = false
    public var downloadProgress: Float = 0

    init(fileId: String, fileName: String, filePath: String, fileLocalPath: String? = nil, accountId: String? = nil) {
        self.accountId = accountId
        self.fileId = fileId
        self.fileName = fileName
        self.filePath = filePath
        self.fileLocalPath = fileLocalPath
    }

    public func isStatus(for messageFileParameter: NCMessageFileParameter, accountId: String) -> Bool {
        return self.accountId == accountId && self.fileId == messageFileParameter.parameterId
    }

    public static func getStatus(from notification: Notification, for messageFileParameter: NCMessageFileParameter, accountId: String) -> NCChatFileStatus? {
        guard let receivedStatus = notification.userInfo?["fileStatus"] as? NCChatFileStatus,
              receivedStatus.isStatus(for: messageFileParameter, accountId: accountId)
        else { return nil }

        return receivedStatus
    }
}
