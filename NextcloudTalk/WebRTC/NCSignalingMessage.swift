//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import CoreFoundation
import Foundation

public let kRoomTypeVideo = "video"
public let kRoomTypeScreen = "screen"

enum SignalingKey {
    static let event = "ev"
    static let function = "fn"
    static let sessionId = "sessionId"
    static let message = "message"

    static let data = "data"
    static let sender = "sender"
    static let typeSession = "session"
    static let externalSessionId = "sessionid"

    static let from = "from"
    static let to = "to"
    static let sid = "sid"
    static let type = "type"
    static let action = "action"
    static let payload = "payload"
    static let roomType = "roomType"
    static let nick = "nick"
    static let status = "status"
    static let broadcaster = "broadcaster"
    static let sdp = "sdp"
    static let reaction = "reaction"
}

enum MessageTypeValue {
    static let offer = "offer"
    static let answer = "answer"
    static let prAnswer = "pranswer"
    static let candidate = "candidate"
    static let unshareScreen = "unshareScreen"
    static let removeCandidates = "remove-candidates"
    static let control = "control"
    static let forceMute = "forceMute"
    static let mute = "mute"
    static let unmute = "unmute"
    static let nickChanged = "nickChanged"
    static let raiseHand = "raiseHand"
    static let recording = "recording"
    static let reaction = "reaction"
    static let startedTyping = "startedTyping"
    static let stoppedTyping = "stoppedTyping"
}

@objcMembers
public class NCSignalingMessage: NSObject {

    public private(set) var from: String!
    public private(set) var to: String!
    public private(set) var sid: String?
    public private(set) var type: String!
    public private(set) var payload: [AnyHashable: Any]!
    public private(set) var roomType: String!
    public var broadcaster: String?

    public init(from: String?, to: String?, sid: String?, type: String?, payload: [AnyHashable: Any]?, roomType: String?, broadcaster: String?) {
        self.from = from
        self.to = to
        self.sid = sid
        self.type = type
        self.payload = payload
        self.roomType = roomType
        self.broadcaster = broadcaster
        super.init()
    }

    // MARK: - Parsing

    public class func messageFromJSONString(_ jsonString: String) -> NCSignalingMessage? {
        guard let data = jsonString.data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [AnyHashable: Any] else {
            NSLog("Error parsing signaling message JSON.")
            return nil
        }

        return self.messageFromJSONDictionary(values)
    }

    public class func messageFromJSONDictionary(_ jsonDict: [AnyHashable: Any]) -> NCSignalingMessage? {
        // Validate before constructing a message: the call controller also uses from/roomType
        // while matching pending offers, before dispatching to the individual message handlers.
        guard jsonDict[SignalingKey.sender] == nil,
              let typeString = jsonDict[SignalingKey.type] as? String,
              validIncomingMessage(type: typeString, values: jsonDict) else {
            return nil
        }

        switch typeString {
        case MessageTypeValue.candidate:
            return NCICECandidateMessage(values: jsonDict)
        case MessageTypeValue.offer, MessageTypeValue.answer:
            return NCSessionDescriptionMessage(values: jsonDict)
        case MessageTypeValue.unshareScreen:
            return NCUnshareScreenMessage(values: jsonDict)
        case MessageTypeValue.control:
            return NCControlMessage(values: jsonDict)
        case MessageTypeValue.mute:
            return NCMuteMessage(values: jsonDict)
        case MessageTypeValue.unmute:
            return NCUnmuteMessage(values: jsonDict)
        case MessageTypeValue.nickChanged:
            return NCNickChangedMessage(values: jsonDict)
        case MessageTypeValue.raiseHand:
            return NCRaiseHandMessage(values: jsonDict)
        case MessageTypeValue.reaction:
            return NCReactionMessage(values: jsonDict)
        default:
            NSLog("Unexpected signaling message type")
            return nil
        }
    }

    public class func messageFromExternalSignalingJSONDictionary(_ jsonDict: [AnyHashable: Any]) -> NCSignalingMessage? {
        guard let data = jsonDict[SignalingKey.data] as? [AnyHashable: Any] else { return nil }

        // Recording/control events are server messages, not peer media messages. They do not
        // require a peer roomType, but their payload must still be usable by their handlers.
        if data[SignalingKey.type] as? String == MessageTypeValue.recording {
            guard let recording = data[MessageTypeValue.recording] as? [AnyHashable: Any],
                  validRecordingStatus(recording[SignalingKey.status]) else { return nil }
            return NCRecordingMessage(values: jsonDict)
        }

        let typeString = data[SignalingKey.type] as? String
        let peerTypes = [MessageTypeValue.unshareScreen, MessageTypeValue.mute, MessageTypeValue.unmute,
                         MessageTypeValue.nickChanged, MessageTypeValue.raiseHand, MessageTypeValue.reaction,
                         MessageTypeValue.candidate, MessageTypeValue.offer, MessageTypeValue.answer]

        if !peerTypes.contains(typeString ?? ""), data[SignalingKey.action] as? String == MessageTypeValue.forceMute {
            guard validControlPayload(data) else { return nil }
            let sender = jsonDict[SignalingKey.sender] as? [AnyHashable: Any]
            return NCControlMessage(from: sender?[SignalingKey.externalSessionId] as? String,
                                    to: data[SignalingKey.to] as? String,
                                    sid: data[SignalingKey.sid] as? String,
                                    roomType: data[SignalingKey.roomType] as? String,
                                    payload: data)
        }

        guard let sender = jsonDict[SignalingKey.sender] as? [AnyHashable: Any],
              let typeString,
              validIncomingMessage(type: typeString, values: jsonDict) else { return nil }

        switch typeString {
        case MessageTypeValue.unshareScreen:
            return NCUnshareScreenMessage(values: jsonDict)
        case MessageTypeValue.mute:
            return NCMuteMessage(values: jsonDict)
        case MessageTypeValue.unmute:
            return NCUnmuteMessage(values: jsonDict)
        case MessageTypeValue.nickChanged:
            return NCNickChangedMessage(values: jsonDict)
        case MessageTypeValue.raiseHand:
            return NCRaiseHandMessage(values: jsonDict)
        case MessageTypeValue.reaction:
            return NCReactionMessage(values: jsonDict)
        default:
            break
        }

        if sender[SignalingKey.type] as? String == SignalingKey.typeSession {
            switch typeString {
            case MessageTypeValue.candidate:
                return NCICECandidateMessage(values: jsonDict)
            case MessageTypeValue.offer, MessageTypeValue.answer:
                return NCSessionDescriptionMessage(values: jsonDict)
            default:
                break
            }
        }

        NSLog("Unexpected external signaling message type")
        return nil
    }

    private static func validIncomingMessage(type: String, values: [AnyHashable: Any]) -> Bool {
        let parsed = parsedValues(from: values)

        if type == MessageTypeValue.control {
            return validControlPayload(parsed.payload)
        }

        guard let from = parsed.from, !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parsed.roomType == kRoomTypeVideo || parsed.roomType == kRoomTypeScreen else {
            return false
        }

        // unshareScreen deliberately has no payload; its handler only needs the peer identity.
        if type == MessageTypeValue.unshareScreen { return true }
        guard let payload = parsed.payload else { return false }

        switch type {
        case MessageTypeValue.offer, MessageTypeValue.answer:
            // A mismatched/pranswer payload would otherwise enter the SDP constructor's
            // unsupported-type assertion, even when the outer message says "offer".
            return payload[SignalingKey.type] as? String == type &&
                (payload[SignalingKey.sdp] as? String)?.isEmpty == false
        case MessageTypeValue.candidate:
            guard let candidate = payload[MessageTypeValue.candidate] as? [AnyHashable: Any],
                  candidate["candidate"] is String,
                  let index = integerValue(candidate["sdpMLineIndex"]), index >= 0, index <= Int32.max else {
                return false
            }
            // An empty candidate is the legitimate end-of-candidates marker. sdpMid is nullable.
            return candidate["sdpMid"] == nil || candidate["sdpMid"] is NSNull || candidate["sdpMid"] is String
        case MessageTypeValue.mute, MessageTypeValue.unmute:
            return ["audio", "video"].contains(payload["name"] as? String ?? "")
        case MessageTypeValue.nickChanged:
            return payload["name"] is String
        case MessageTypeValue.raiseHand:
            guard let state = payload["state"] as? NSNumber else { return false }
            return CFGetTypeID(state) == CFBooleanGetTypeID()
        case MessageTypeValue.reaction:
            return (payload[SignalingKey.reaction] as? String)?.isEmpty == false
        default:
            return false
        }
    }

    private static func validControlPayload(_ payload: [AnyHashable: Any]?) -> Bool {
        return payload?[SignalingKey.action] as? String == MessageTypeValue.forceMute &&
            (payload?["peerId"] as? String)?.isEmpty == false
    }

    private static func integerValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number.doubleValue)
    }

    private static func validRecordingStatus(_ value: Any?) -> Bool {
        if let string = value as? String { return Int(string) != nil }
        return integerValue(value) != nil
    }

    public class func getMessageSid() -> String {
        let timeStamp = Date().timeIntervalSince1970
        return NSNumber(value: timeStamp).stringValue
    }

    // MARK: - Serialization

    public override var description: String {
        if let data = self.jsonData(), let string = String(data: data, encoding: .utf8) {
            return string
        }

        return super.description
    }

    func jsonData() -> Data? {
        return try? JSONSerialization.data(withJSONObject: self.messageDict(), options: [])
    }

    func functionJSONSerialization() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: self.functionDict(), options: []),
              let string = String(data: data, encoding: .utf8) else {
            NSLog("Error serializing JSON")
            return ""
        }

        return string
    }

    public func messageDict() -> [AnyHashable: Any] {
        return [
            SignalingKey.event: SignalingKey.message,
            SignalingKey.function: self.functionJSONSerialization(),
            SignalingKey.sessionId: self.from ?? ""
        ]
    }

    public func functionDict() -> [AnyHashable: Any] {
        return [
            SignalingKey.to: self.to ?? "",
            SignalingKey.roomType: self.roomType ?? "",
            SignalingKey.type: self.type ?? "",
            SignalingKey.sid: self.sid ?? "",
            SignalingKey.payload: self.payload ?? [:]
        ]
    }

    public func messageType() -> NCSignalingMessageType {
        return .unknown
    }

    // MARK: - Helpers

    struct ParsedValues {
        let from: String?
        let to: String?
        let sid: String?
        let roomType: String?
        let broadcaster: String?
        let payload: [AnyHashable: Any]?
    }

    // Extracts the common signaling values, taking into account that when using an external signaling
    // server the relevant values are nested in the "data" dictionary and "from" comes from the "sender".
    static func parsedValues(from values: [AnyHashable: Any], useDataAsPayload: Bool = false) -> ParsedValues {
        var dataDict = values
        var from = values[SignalingKey.from] as? String
        var payload = values[SignalingKey.payload] as? [AnyHashable: Any]

        if let sender = values[SignalingKey.sender] as? [AnyHashable: Any] {
            from = sender[SignalingKey.externalSessionId] as? String
            dataDict = values[SignalingKey.data] as? [AnyHashable: Any] ?? [:]
            payload = useDataAsPayload ? dataDict : (dataDict[SignalingKey.payload] as? [AnyHashable: Any])
        }

        return ParsedValues(from: from,
                            to: dataDict[SignalingKey.to] as? String,
                            sid: dataDict[SignalingKey.sid] as? String,
                            roomType: dataDict[SignalingKey.roomType] as? String,
                            broadcaster: dataDict[SignalingKey.broadcaster] as? String,
                            payload: payload)
    }
}
