//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Downloads files of conversations, sharing one download between all callers asking for the same file.
///
/// Does not offer cancellation on purpose: the download is shared, so one caller losing interest
/// must not stop it for the others.
public class ChatFileDownloader: NSObject {
    struct FileIdentity: Hashable {
        let accountId: String
        let fileId: String
    }

    private var completionHandlers = [FileIdentity: [NCChatFileController.CompletionHandler]]()
    private var fileControllers = [FileIdentity: NCChatFileController]()

    static let shared = ChatFileDownloader()
    private let makeController: (TalkAccount) -> NCChatFileController

    init(makeController: @escaping (TalkAccount) -> NCChatFileController = { NCChatFileController(account: $0) }) {
        self.makeController = makeController
        super.init()
    }

    @MainActor
    public func downloadFile(withFileId fileId: String, fromAccount account: TalkAccount, completionHandler: @escaping NCChatFileController.CompletionHandler) {
        let identity = FileIdentity(accountId: account.accountId, fileId: fileId)
        completionHandlers[identity, default: []].append(completionHandler)

        // We are already downloading this file, don't do it again, the handler above is called once it finishes
        guard fileControllers[identity] == nil else { return }

        let fileController = self.makeController(account)
        fileControllers[identity] = fileController

        fileController.downloadFile(withFileId: fileId) { [weak self] result in
            self?.executeCompletionHandlers(for: identity, with: result)
        }
    }

    @MainActor
    public func downloadStatus(forFileId fileId: String, accountId: String) -> NCChatFileStatus? {
        return fileControllers[FileIdentity(accountId: accountId, fileId: fileId)]?.fileStatus
    }

    private func executeCompletionHandlers(for identity: FileIdentity, with result: Result<NCChatFileStatus, ChatFileDownloadError>) {
        DispatchQueue.main.async { [self] in
            fileControllers.removeValue(forKey: identity)

            guard let handlers = completionHandlers.removeValue(forKey: identity) else { return }

            for handler in handlers {
                handler(result)
            }
        }
    }
}
