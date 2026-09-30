import CryptoKit
import Foundation

/// Builds the `/events` request body and its HMAC signature.
///
/// The server verifies the signature over `JSON.stringify(JSON.parse(rawBody))`, so the body we
/// send must already be in that exact form: compact and with strings escaped the way JavaScript
/// escapes them. A generic JSON encoder escapes `/` as `\/`, which the server would re-serialize
/// differently and reject — hence the hand-written `jsonString`.
enum EventSigner {

    static func hmacHex(secret: String, body: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(body.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    static func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    static func buildBody(
        eventType: String,
        brandId: String,
        playerId: String,
        payload: [(String, String)],
        eventId: String,
        idempotencyKey: String,
        occurredAt: String
    ) -> String {
        let payloadJson = payload
            .map { "\(jsonString($0.0)):\(jsonString($0.1))" }
            .joined(separator: ",")
        return "{"
            + "\"schema_version\":\"1.0\","
            + "\"event_id\":\(jsonString(eventId)),"
            + "\"event_type\":\(jsonString(eventType)),"
            + "\"brand_id\":\(jsonString(brandId)),"
            + "\"source_system\":\"ios-sdk\","
            + "\"occurred_at\":\(jsonString(occurredAt)),"
            + "\"player_ref\":{\"external_player_id\":\(jsonString(playerId))},"
            + "\"payload\":{\(payloadJson)},"
            + "\"idempotency_key\":\(jsonString(idempotencyKey))"
            + "}"
    }
}
