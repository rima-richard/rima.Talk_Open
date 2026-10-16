//
// SPDX-FileCopyrightText: 2026 rima Pflege GmbH
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import WebRTC
@testable import NextcloudTalk

final class UnitSecuritySignalingTest: XCTestCase {
    func testCallDiagnosticSummaryDoesNotExposeSignalingContents() {
        let secret = "sensitive-peer-sdp-address-marker"
        let values: [AnyHashable: Any] = [
            "sender": ["sessionid": secret],
            "data": ["type": "offer", "roomType": "video", "sid": secret,
                     "payload": ["type": "offer", "sdp": secret, "candidate": ["candidate": secret, "sdpMLineIndex": 0]]]
        ]
        let summary = NCSignalingMessage.safeDiagnosticSummary(values)
        XCTAssertFalse(summary.contains(secret))
        XCTAssertTrue(summary.contains("type=offer"))
        XCTAssertTrue(summary.contains("index=integer"))

        let unknown: [AnyHashable: Any] = ["type": secret, "roomType": secret, "from": secret,
                                         "payload": ["type": secret, "sdp": secret]]
        XCTAssertFalse(NCSignalingMessage.safeDiagnosticSummary(unknown).contains(secret))
    }

    private let peerId = "synthetic-peer-session"
    private let sdp = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"

    private func peerMessage(_ type: String, payload: [AnyHashable: Any]? = nil, roomType: String = kRoomTypeVideo) -> [AnyHashable: Any] {
        var values: [AnyHashable: Any] = ["type": type, "from": peerId, "roomType": roomType, "sid": "synthetic-call"]
        if let payload { values["payload"] = payload }
        return values
    }

    private func external(_ internalMessage: [AnyHashable: Any], senderType: String = "session") -> [AnyHashable: Any] {
        var data = internalMessage
        let from = data.removeValue(forKey: "from")
        var sender: [AnyHashable: Any] = ["type": senderType]
        if let from { sender["sessionid"] = from }
        return ["data": data, "sender": sender]
    }

    private func parseBoth(_ message: [AnyHashable: Any]) -> [NCSignalingMessage?] {
        return [NCSignalingMessage.messageFromJSONDictionary(message),
                NCSignalingMessage.messageFromExternalSignalingJSONDictionary(external(message))]
    }

    private var validPeerMessages: [[AnyHashable: Any]] {
        return [
            peerMessage("offer", payload: ["type": "offer", "sdp": sdp]),
            peerMessage("answer", payload: ["type": "answer", "sdp": sdp]),
            peerMessage("candidate", payload: ["candidate": ["candidate": "candidate:1 1 UDP 2122260223 192.0.2.1 50000 typ host", "sdpMid": "0", "sdpMLineIndex": 0]]),
            peerMessage("mute", payload: ["name": "audio"]),
            peerMessage("unmute", payload: ["name": "video"]),
            peerMessage("nickChanged", payload: ["name": "Synthetic colleague"]),
            peerMessage("raiseHand", payload: ["state": true, "timestamp": "123456"]),
            peerMessage("reaction", payload: ["reaction": "👍"]),
            peerMessage("unshareScreen", roomType: kRoomTypeScreen)
        ]
    }

    func testMissingRoomTypeMuteIsRejectedBeforeCallDispatch() {
        var values = peerMessage("mute", payload: ["name": "audio"])
        values.removeValue(forKey: "roomType")
        for message in parseBoth(values) { XCTAssertNil(message) }
    }

    func testEveryPeerMessageRequiresSenderAndKnownRoomTypeInBothTransports() {
        for validMessage in validPeerMessages {
            for field in ["from", "roomType"] {
                var missing = validMessage
                missing.removeValue(forKey: field)
                for message in parseBoth(missing) { XCTAssertNil(message, "Missing \(field): \(validMessage["type"]!)") }

                for badValue: Any in [NSNull(), 7, "", "   "] {
                    var malformed = validMessage
                    malformed[field] = badValue
                    for message in parseBoth(malformed) { XCTAssertNil(message, "Invalid \(field): \(validMessage["type"]!)") }
                }
            }

            var unknownRoom = validMessage
            unknownRoom["roomType"] = "unknown-room-kind"
            for message in parseBoth(unknownRoom) { XCTAssertNil(message) }
        }
    }

    func testValidAudioVideoAndScreenMessagesRemainUsableByCallHandlers() throws {
        for fixture in validPeerMessages {
            for roomType in [kRoomTypeVideo, kRoomTypeScreen] {
                var values = fixture
                values["roomType"] = roomType
                for message in parseBoth(values) {
                    let message = try XCTUnwrap(message)
                    XCTAssertEqual(message.from, peerId)
                    XCTAssertEqual(message.roomType, roomType)
                    // These values are used as nonoptional strings even before offer dispatch.
                    let sender: String = message.from
                    let mediaRoom: String = message.roomType
                    XCTAssertEqual(sender + mediaRoom, peerId + roomType)
                }
            }
        }
    }

    func testMalformedPayloadsAreRejectedInBothTransports() {
        let invalid: [[AnyHashable: Any]] = [
            peerMessage("mute"),
            peerMessage("mute", payload: ["name": NSNull()]),
            peerMessage("unmute", payload: ["name": "unknown-media"]),
            peerMessage("nickChanged", payload: ["name": 7]),
            peerMessage("raiseHand", payload: ["state": "true"]),
            peerMessage("raiseHand", payload: ["state": 1]),
            peerMessage("reaction", payload: ["reaction": ["unexpected"]]),
            peerMessage("reaction", payload: [:])
        ]
        for values in invalid {
            for message in parseBoth(values) { XCTAssertNil(message) }
        }
    }

    func testSDPRequiresMatchingSupportedTypeBeforeWebRTCConstruction() throws {
        for outerType in ["offer", "answer"] {
            for innerType in ["pranswer", "rollback", "unknown", outerType == "offer" ? "answer" : "offer"] {
                let values = peerMessage(outerType, payload: ["type": innerType, "sdp": sdp])
                for message in parseBoth(values) { XCTAssertNil(message) }
            }
            for payload: [AnyHashable: Any] in [["type": outerType], ["type": outerType, "sdp": 1], ["type": outerType, "sdp": ""], ["sdp": sdp]] {
                for message in parseBoth(peerMessage(outerType, payload: payload)) { XCTAssertNil(message) }
            }

            for message in parseBoth(peerMessage(outerType, payload: ["type": outerType, "sdp": sdp])) {
                let descriptionMessage = try XCTUnwrap(message as? NCSessionDescriptionMessage)
                XCTAssertEqual(descriptionMessage.sessionDescription.sdp, sdp)
                XCTAssertEqual(descriptionMessage.sessionDescription.type, outerType == "offer" ? .offer : .answer)
            }
        }
    }

    func testICERejectsMalformedIndexesAndPreservesEndOfCandidates() throws {
        let baseCandidate: [AnyHashable: Any] = ["candidate": "", "sdpMLineIndex": 0, "sdpMid": NSNull()]
        for badValue: Any in [NSNull(), true, -1, 0.5, Double(Int32.max) + 1, "0"] {
            var candidate = baseCandidate
            candidate["sdpMLineIndex"] = badValue
            for message in parseBoth(peerMessage("candidate", payload: ["candidate": candidate])) { XCTAssertNil(message) }
        }
        var missingIndex = baseCandidate
        missingIndex.removeValue(forKey: "sdpMLineIndex")
        for message in parseBoth(peerMessage("candidate", payload: ["candidate": missingIndex])) { XCTAssertNil(message) }

        var invalidMid = baseCandidate
        invalidMid["sdpMid"] = ["not-a-string"]
        for message in parseBoth(peerMessage("candidate", payload: ["candidate": invalidMid])) { XCTAssertNil(message) }

        for message in parseBoth(peerMessage("candidate", payload: ["candidate": baseCandidate])) {
            let candidateMessage = try XCTUnwrap(message as? NCICECandidateMessage)
            XCTAssertEqual(candidateMessage.candidate.sdp, "")
            XCTAssertEqual(candidateMessage.candidate.sdpMLineIndex, 0)
            XCTAssertNil(candidateMessage.candidate.sdpMid)
        }
    }

    func testPayloadFreeUnshareAndRoomBroadcastEventsStaySupported() throws {
        let unshare = peerMessage("unshareScreen", roomType: kRoomTypeVideo)
        for message in parseBoth(unshare) { XCTAssertEqual(try XCTUnwrap(message).messageType(), .unshareScreen) }

        let broadcast = external(peerMessage("raiseHand", payload: ["state": false]), senderType: "room")
        XCTAssertEqual(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(broadcast)?.messageType(), .raiseHand)

        let nonSessionOffer = external(peerMessage("offer", payload: ["type": "offer", "sdp": sdp]), senderType: "room")
        XCTAssertNil(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(nonSessionOffer))
    }

    func testServerRecordingAndForceMuteDoNotRequirePeerRoomType() throws {
        for status: Any in [0, "1"] {
            let values: [AnyHashable: Any] = ["data": ["type": "recording", "recording": ["status": status]]]
            XCTAssertNotNil(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(values) as? NCRecordingMessage)
        }
        for status: Any in [true, "not-a-status", 1.5, NSNull()] {
            let values: [AnyHashable: Any] = ["data": ["type": "recording", "recording": ["status": status]]]
            XCTAssertNil(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(values))
        }

        let controlPayload: [AnyHashable: Any] = ["action": "forceMute", "peerId": peerId]
        for values: [AnyHashable: Any] in [["data": controlPayload], ["data": controlPayload, "sender": ["type": "room"]]] {
            let message = try XCTUnwrap(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(values))
            XCTAssertEqual(message.messageType(), .control)
            XCTAssertEqual(message.payload["peerId"] as? String, peerId)
        }
        XCTAssertNotNil(NCSignalingMessage.messageFromJSONDictionary(["type": "control", "payload": controlPayload]))
        XCTAssertNil(NCSignalingMessage.messageFromJSONDictionary(["type": "control"]))
        XCTAssertNil(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(["data": ["action": "forceMute"]]))
    }

    func testMalformedJSONAndMixedEnvelopesFailClosed() throws {
        for json in ["null", "[]", "1", "{", "{}"] { XCTAssertNil(NCSignalingMessage.messageFromJSONString(json)) }
        XCTAssertNil(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(["data": "not-an-object"]))
        XCTAssertNil(NCSignalingMessage.messageFromExternalSignalingJSONDictionary(["data": ["type": "mute", "roomType": "video", "payload": ["name": "audio"]]]))

        var hybrid = peerMessage("mute", payload: ["name": "audio"])
        hybrid["sender"] = ["sessionid": peerId]
        XCTAssertNil(NCSignalingMessage.messageFromJSONDictionary(hybrid))

        let valid = peerMessage("mute", payload: ["name": "audio"])
        let json = try JSONSerialization.data(withJSONObject: valid)
        XCTAssertEqual(NCSignalingMessage.messageFromJSONString(try XCTUnwrap(String(data: json, encoding: .utf8)))?.messageType(), .mute)
    }
}
