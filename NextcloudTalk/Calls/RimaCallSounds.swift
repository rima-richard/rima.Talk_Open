// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation

extension Notification.Name {
    static let rimaCallToneDidChange = Notification.Name("RimaCallToneDidChange")
}

enum RimaCallTone: String, CaseIterable {
    case resonanz, bogen

    var title: String { self == .resonanz ? "Resonanz" : "Bogen" }
    var fileName: String { self == .resonanz ? "05-anruf-resonanz.wav" : "06-anruf-bogen.wav" }
    static let preferenceKey = "rima.call.ringtone.v1"

    static func selected(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .resonanz
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
        NotificationCenter.default.post(name: .rimaCallToneDidChange, object: nil)
    }
}

enum RimaCallSounds {
    /// Same gentle call-progress signal as Workspace: 1s at 440 Hz, 4s silence.
    /// This does not confirm that the remote device is audibly ringing.
    static func outgoingPlayer() -> AVAudioPlayer? {
        let rate = 16_000, count = 80_000
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(rate)); word(UInt32(rate * 2)); word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(UInt32(count * 2))
        for sample in 0..<count {
            let envelope = sample < rate ? min(1, Double(sample) / 160, Double(rate - sample) / 160) : 0
            word(Int16(sin(Double(sample) * 2 * .pi * 440 / Double(rate)) * 3200 * envelope))
        }
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        player.numberOfLoops = -1
        player.volume = 0.45
        return player
    }
}
