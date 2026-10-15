// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import SwiftyRSA
import UserNotifications
@testable import NextcloudTalk

final class UnitSecurityNotificationTest: XCTestCase {
    private var account: TalkAccount!

    override func setUpWithError() throws {
        account = TalkAccount()
        account.accountId = "security-test-\(UUID().uuidString)"
        account.user = "synthetic-review"
        account.server = "https://account.example/nextcloud"
    }

    override func tearDownWithError() throws {
        for prefix in ["ncPNPrivateKey", "ncPNPublicKey", "ncToken"] {
            NCKeyChainController.sharedInstance().keychain.removeItem(forKey: "\(prefix)-\(account.accountId)")
        }
    }

    private func envelope(padding: Padding = .OAEP) throws -> [AnyHashable: Any] {
        let server = try SwiftyRSA.generateRSAKeyPair(sizeInBits: 2048)
        let device = try SwiftyRSA.generateRSAKeyPair(sizeInBits: 2048)
        account.userPublicKey = try server.publicKey.pemStringPkcs8()
        NCKeyChainController.sharedInstance().setPushNotificationPrivateKey(try device.privateKey.pemStringPkcs8().data(using: .utf8)!, forAccountId: account.accountId)
        let clear = try ClearMessage(string: "{\"app\":\"spreed\",\"type\":\"reminder\",\"subject\":\"Test\",\"id\":\"room123\",\"nid\":42}", using: .utf8)
        let encrypted = try clear.encrypted(with: device.publicKey, padding: padding)
        return ["subject": encrypted.base64String, "signature": try encrypted.signed(with: server.privateKey, digestType: .sha512).base64String]
    }

    func testForgedDerivedMetadataCannotAuthenticate() {
        let forged: [AnyHashable: Any] = ["accountId": account.accountId, "pushNotification": "{\"app\":\"spreed\",\"type\":\"reminder\",\"nid\":42}", "serverNotification": ["actions": [["type": "DELETE", "link": "https://other.example/steal"]]], "localNotificationType": 1]
        XCTAssertNil(NCPushNotificationsUtils.verifiedPushNotification(from: forged, accounts: [account]))
        XCTAssertTrue(NCPushNotificationsUtils.signedEnvelope(from: forged).isEmpty)
        XCTAssertFalse(NCNotificationController.isLocallyScheduled(nil))
        XCTAssertTrue(NCNotificationController.isLocallyScheduled(UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    func testSignedEnvelopeSelectsAccountIgnoringForgedMetadata() throws {
        var input = try envelope()
        input["accountId"] = "attacker-selected-account"
        input["pushNotification"] = "{\"app\":\"spreed\",\"id\":\"other-room\"}"
        input["serverNotification"] = ["actions": [["link": "https://other.example/steal"]]]
        let push = try XCTUnwrap(NCPushNotificationsUtils.verifiedPushNotification(from: input, accounts: [account]))
        XCTAssertEqual(push.accountId, account.accountId)
        XCTAssertEqual(push.roomToken, "room123")
        XCTAssertEqual(push.notificationId, 42)
        XCTAssertEqual(Set(NCPushNotificationsUtils.signedEnvelope(from: input).keys), ["subject", "signature"])
        let server = NCNotification(dictionary: ["notification_id": 42, "app": "spreed", "object_id": "room123/7", "object_type": "reminder"])
        XCTAssertTrue(NCNotificationController.matches(server, push: push))
        server?.notificationId = 43
        XCTAssertFalse(NCNotificationController.matches(server, push: push))
        server?.notificationId = 42
        server?.objectId = "different-room"
        XCTAssertFalse(NCNotificationController.matches(server, push: push))
    }

    func testTamperedSignatureAndCiphertextFailClosed() throws {
        let original = try envelope()
        var input = original
        input["signature"] = Data(repeating: 0, count: 256).base64EncodedString()
        XCTAssertNil(NCPushNotificationsUtils.verifiedPushNotification(from: input, accounts: [account]))
        input = original
        input["subject"] = Data(repeating: 0, count: 256).base64EncodedString()
        XCTAssertNil(NCPushNotificationsUtils.verifiedPushNotification(from: input, accounts: [account]))
    }

    func testLegacySignedPushRemainsSupported() throws {
        XCTAssertNotNil(NCPushNotificationsUtils.verifiedPushNotification(from: try envelope(padding: .PKCS1), accounts: [account]))
    }

    func testActionOriginAndEquivalentRepresentations() {
        let allowed = ["https://account.example/action", "https://ACCOUNT.example:443/action?x=1"]
        for link in allowed { XCTAssertNotNil(NCAPIController.notificationActionURL(link, accountServer: account.server)) }
        let denied = ["https://other.example/action", "https://account.example.other.example/", "https://account.example@other.example/", "https://user:password@account.example/", "http://account.example/", "https://account.example:444/", "//account.example/", "/action", "https://account.example/action#fragment", "file:///tmp/file"]
        for link in denied {
            XCTAssertNil(NCAPIController.notificationActionURL(link, accountServer: account.server), link)
            let action = NCNotificationAction(dictionary: ["type": "DELETE", "link": link])
            var completed = false
            NCAPIController.shared.executeNotificationAction(action, forAccount: account) { error in
                XCTAssertNotNil(error)
                completed = true
            }
            XCTAssertTrue(completed, "Rejected before credentials or networking")
        }
        XCTAssertNotNil(NCAPIController.notificationActionURL("http://localhost:8080/action", accountServer: "http://localhost:8080"))
    }

    func testActionSessionAuthenticatesControlAndRejectsRedirect() throws {
        NCKeyChainController.sharedInstance().setToken("synthetic-token", forAccountId: account.accountId)
        let controller = NCAPIController()
        let manager = try XCTUnwrap(controller.notificationActionSession(forAccount: account))
        defer { manager.invalidateSessionCancelingTasks(true) }
        let url = try XCTUnwrap(NCAPIController.notificationActionURL("https://account.example/action", accountServer: account.server))
        let request = manager.requestSerializer.request(withMethod: "DELETE", urlString: url.absoluteString, parameters: nil, error: nil)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("synthetic-review:synthetic-token".utf8).base64EncodedString())
        let task = manager.session.dataTask(with: url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://other.example/steal"]))
        let completion = expectation(description: "redirect refused")
        manager.urlSession(manager.session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://other.example/steal")!)) { redirected in
            XCTAssertNil(redirected)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 2)
    }
}
