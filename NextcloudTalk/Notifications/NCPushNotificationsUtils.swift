//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftyRSA

@objcMembers
public class NCPushNotificationsUtils: NSObject {

    /// Only the signed envelope is transport input. Derived account/action metadata is never proof of origin.
    public static func signedEnvelope(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var envelope: [String: String] = [:]
        envelope["subject"] = userInfo["subject"] as? String
        envelope["signature"] = userInfo["signature"] as? String
        return envelope
    }

    public static func verifiedPushNotification(from userInfo: [AnyHashable: Any], accounts: [TalkAccount]) -> NCPushNotification? {
        guard let message = userInfo["subject"] as? String,
              let signature = userInfo["signature"] as? String else { return nil }

        for account in accounts {
            guard let decrypted = decryptPushNotification(withMessageBase64: message, withSignatureBase64: signature, forAccount: account),
                  let data = decrypted.data(using: .utf8),
                  let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  dictionary["app"] is String else { continue }
            // Keep malformed signed payloads out of the Objective-C notification parser.
            let stringFields = ["app", "type", "subject", "id"]
            guard stringFields.allSatisfy({ dictionary[$0] == nil || dictionary[$0] is String }),
                  dictionary["nid"] == nil || dictionary["nid"] is NSNumber || dictionary["nid"] is String else { continue }
            if let notification = NCPushNotification(fromDecryptedString: decrypted, withAccountId: account.accountId) {
                return notification
            }
        }
        return nil
    }

    public static func decryptPushNotification(withMessageBase64 messageBase64: String, withSignatureBase64 signatureBase64: String, forAccount account: TalkAccount) -> String? {
        do {
            guard let userPublicKeyPem = account.userPublicKey else { return nil }

            let encryptedMessage = try EncryptedMessage(base64Encoded: messageBase64)
            let userPublicKey = try RsaPublicKey(pemEncoded: userPublicKeyPem)
            let signature = try Signature(base64Encoded: signatureBase64)

            guard try encryptedMessage.verify(with: userPublicKey, signature: signature, digestType: .sha512) else {
                return nil
            }

            guard let devicePrivateKeyData = NCKeyChainController.sharedInstance().pushNotificationPrivateKey(forAccountId: account.accountId),
                  let devicePrivateKeyPem = String(data: devicePrivateKeyData, encoding: .utf8) else {
                return nil
            }

            let devicePrivateKey = try RsaPrivateKey(pemEncoded: devicePrivateKeyPem)

            do {
                let clearMessage = try encryptedMessage.decrypted(with: devicePrivateKey, padding: .OAEP)
                return try clearMessage.string(encoding: .utf8)
            } catch {
                // If decrypting with OAEP fails, try again with legacy PKCS1
                let clearMessage = try encryptedMessage.decrypted(with: devicePrivateKey, padding: .PKCS1)
                return try clearMessage.string(encoding: .utf8)
            }
        } catch {
            print("decryptPushNotificationError: \(error)")
        }

        return nil
    }

    public static func generatePushNotificationKeyPair() -> NCPushNotificationKeyPair? {
        do {
            let keyPair = try SwiftyRSA.generateRSAKeyPair(sizeInBits: 2048)

            let privateKeyPem = try keyPair.privateKey.pemStringPkcs8()
            let publicKeyPem = try keyPair.publicKey.pemStringPkcs8()

            return NCPushNotificationKeyPair(privateKey: privateKeyPem.data(using: .utf8)!, publicKey: publicKeyPem.data(using: .utf8)!)
        } catch {
            NCLog.log("Error generating push keypair: \(error)")
        }

        return nil
    }

}
