//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

extension NCAppBranding {

    @objc
    static func elementColorBackground() -> UIColor {
        var lightColor: UIColor
        var darkColor: UIColor

        if #available(iOS 18.0, *) {
            lightColor = NCAppBranding.elementColor().withProminence(.quaternary)
            darkColor = NCAppBranding.elementColor().withProminence(.secondary)
        } else {
            lightColor = NCAppBranding.elementColor().withAlphaComponent(0.1)
            darkColor = NCAppBranding.elementColor().withAlphaComponent(0.2)
        }

        return NCAppBranding.getDynamicColor(lightColor, withDarkMode: darkColor)
    }

    @objc
    static func userAgent() -> String {
        return "Mozilla/5.0 (iOS) Nextcloud-Talk v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown")"
    }

    @objc
    static func userAgentForLogin() -> String {
        let appDisplayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] ?? "Unknown app"
        let deviceName = UIDevice.current.name

        return "\(deviceName) (\(appDisplayName))"
    }

}

#if DEBUG
// Development-only bounded diagnostics: no tokens, identifiers, keys, URLs or account data.
enum RimaPushDiagnostics {
    private static let queue = DispatchQueue(label: "de.rima.chat.push-diagnostics")
    static func record(_ values: [String: Any]) {
        queue.async {
            guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let url = folder.appendingPathComponent("rima-push-diagnostics.json")
            var state = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            for (key, value) in values { state[key] = value }
            state["build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }
    static func errorStatus(_ error: Error) {
        let e = error as NSError
        let response = e.userInfo[AFNetworkingOperationFailingURLResponseErrorKey] as? HTTPURLResponse
        var code = "UNCLASSIFIED"
        if let data = e.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] as? Data,
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let candidate = object["error"] as? String,
           candidate.range(of: "^[A-Z_]{1,64}$", options: .regularExpression) != nil {
            code = candidate
        }
        record(["proxy_http_status": response?.statusCode ?? 0, "proxy_error_code": code, "proxy_error_number": e.code])
    }
}
#endif
