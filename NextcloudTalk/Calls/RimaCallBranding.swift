//
// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers final class RimaCallAppearance: NSObject {
    static let backgroundColor = UIColor(white: 0.025, alpha: 1)
    static let surfaceColor = UIColor(white: 0.085, alpha: 1)
    static let avatarColor = UIColor(white: 0.14, alpha: 1)
}

enum RimaCallBranding {

    /// CallKit uses an alpha mask, unlike the opaque, full-color notification app icon.
    static func callKitIconData() -> Data? {
        guard let symbol = UIImage(named: "RimaCallKitSymbol") else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(origin: .zero, size: size))
        }.pngData()
    }
}
