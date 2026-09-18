import Foundation

/// Builds the binary wire packets exactly as the Android app does
/// (see MainActivity.kt: `transmitJsonState` / `transmitPlainCommand`).
///
/// State packet layout: 60 bytes, little-endian, always zero-padded at the end.
/// Plain command packet layout: 10 bytes.
struct PacketEncoder {

    enum ActionCommand: UInt8 {
        case refreshEsp = 0x01
        case refreshEntities = 0x02
        case bypassOn = 0x03
        case bypassOff = 0x04
        case memoryInit = 0x05
        case cleanEvent8 = 0x06
    }

    /// 60-byte state packet (@ MainActivity.kt transmitJsonState).
    static func statePacket(jsonString: String) -> Data? {
        guard
            let data = jsonString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var packet = [UInt8](repeating: 0, count: 60)

        // Header: AC DC 01 00 <int32 LE length=60>
        packet[0] = 0xAC
        packet[1] = 0xDC
        packet[2] = 0x01
        packet[3] = 0x00
        writeInt32LE(60, into: &packet, at: 4)

        // Aimbot section
        if let aimbot = object["aimbot"] as? [String: Any] {
            var index = 8
            packet[index] = boolByte(aimbot["active"])            // active
            packet[index + 1] = aimbotTypeByte(aimbot["type"])    // type
            packet[index + 2] = UInt8(clamping: intValue(aimbot["fov"], default: 12) & 0xFF)
            packet[index + 3] = 0                                 // reserved (was realPower)
            packet[index + 4] = boolByte(aimbot["sniperScope"])   // sniperScope
            packet[index + 5] = 0                                 // dragSensitivity (not used)
            writeInt16LE(intValue(aimbot["dragDelay"], default: 80), into: &packet, at: index + 6)

            index += 8
            let external = object["externalAimbot"] as? [String: Any]
            let aimOnHeadMs = external.flatMap { $0["aimOnHeadMs"] }.map { intValue($0, default: 100) } ?? 100
            let dragThreshold = external.flatMap { $0["dragThreshold"] }.map { intValue($0, default: 5) } ?? 5

            writeInt16LE(aimOnHeadMs, into: &packet, at: index)                     // aimOnHeadMs
            writeInt16LE(intValue(aimbot["colliderDelay"], default: 0), into: &packet, at: index + 2)
            writeInt16LE(intValue(aimbot["fairDelay"], default: 6), into: &packet, at: index + 4)
            packet[index + 6] = UInt8(clamping: intValue(aimbot["fairBrutality"], default: 0) & 0xFF)
            packet[index + 7] = UInt8(clamping: intValue(aimbot["fairTargetBone"], default: 0) & 0xFF)
            packet[index + 8] = 0                                // dragLegitBind
            packet[index + 9] = 0                                // dragScopeMode
            packet[index + 10] = UInt8(clamping: dragThreshold & 0xFF)

            // Offsets 8..35 (28 bytes) written; 36..59 stay zeroed.
        }

        // ESP section (offsets 36..43)
        if let esp = object["esp"] as? [String: Any] {
            packet[36] = boolByte(esp["active"])
            packet[37] = boolByte(esp["box"])
            packet[38] = boolByte(esp["distance"])
            packet[39] = boolByte(esp["lines"])
            packet[40] = boolByte(esp["info"])
            packet[41] = boolByte(esp["health"])
            // offsets 42..43 reserved, stay zero
        }

        return Data(packet)
    }

    /// 10-byte plain command packet (@ MainActivity.kt transmitPlainCommand).
    static func plainCommandPacket(action: String, arg: String) -> Data {
        var packet = [UInt8](repeating: 0, count: 10)
        packet[0] = 0xAC
        packet[1] = 0xDC
        packet[2] = 0x04
        packet[3] = 0x00
        writeInt32LE(10, into: &packet, at: 4)

        let command: ActionCommand
        switch action {
        case "refresh_esp": command = .refreshEsp
        case "refresh_entities": command = .refreshEntities
        case "pc_bypass": command = (arg == "enabled") ? .bypassOn : .bypassOff
        case "memory_init": command = .memoryInit
        case "clean_event_8": command = .cleanEvent8
        default: command = .refreshEsp
        }
        packet[8] = command.rawValue
        packet[9] = 0x00
        return Data(packet)
    }

    // MARK: - Helpers

    private static func boolByte(_ value: Any?) -> UInt8 {
        guard let v = value else { return 0 }
        if let b = v as? Bool { return b ? 1 : 0 }
        if let s = v as? String, s.lowercased() == "true" { return 1 }
        if let n = v as? NSNumber, n.boolValue { return 1 }
        return 0
    }

    private static func intValue(_ value: Any?, default fallback: Int) -> Int {
        guard let v = value else { return fallback }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let parsed = Int(s) { return parsed }
        return fallback
    }

    /// Maps aimbot type string -> byte exactly like Android.
    private static func aimbotTypeByte(_ value: Any?) -> UInt8 {
        guard let v = value else { return 0 }
        let type = v as? String
        switch type {
        case "head": return 2
        case "fair": return 3
        case "collider": return 4
        case "external": return 5
        default: return 0
        }
    }

    private static func writeInt32LE(_ value: Int, into packet: inout [UInt8], at offset: Int) {
        let v = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
        packet[offset] = UInt8(v & 0xFF)
        packet[offset + 1] = UInt8((v >> 8) & 0xFF)
        packet[offset + 2] = UInt8((v >> 16) & 0xFF)
        packet[offset + 3] = UInt8((v >> 24) & 0xFF)
    }

    private static func writeInt16LE(_ value: Int, into packet: inout [UInt8], at offset: Int) {
        let v = UInt16(truncatingIfNeeded: value)
        packet[offset] = UInt8(v & 0xFF)
        packet[offset + 1] = UInt8((v >> 8) & 0xFF)
    }
}