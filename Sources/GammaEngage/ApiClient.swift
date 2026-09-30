import Foundation

protocol Transport: Sendable {
    /// Calls `completion` with the HTTP status code, or nil when the request failed outright.
    func send(_ request: URLRequest, completion: @escaping @Sendable (Int?) -> Void)
}

struct URLSessionTransport: Transport {
    func send(_ request: URLRequest, completion: @escaping @Sendable (Int?) -> Void) {
        URLSession.shared.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode)
        }.resume()
    }
}

final class ApiClient: @unchecked Sendable {
    private let config: GammaEngageConfig
    private let transport: Transport
    private let baseURL: String

    init(config: GammaEngageConfig, transport: Transport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
        var base = config.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        self.baseURL = base
    }

    func sendEvent(
        type: String,
        playerId: String,
        payload: [(String, String)],
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        let body = EventSigner.buildBody(
            eventType: type,
            brandId: config.brandId,
            playerId: playerId,
            payload: payload,
            eventId: UUID().uuidString.lowercased(),
            idempotencyKey: UUID().uuidString.lowercased(),
            occurredAt: Self.isoNow()
        )
        guard let url = URL(string: "\(baseURL)/events") else {
            log("invalid baseURL")
            completion?(false)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Tenant-API-Key")
        if let secret = config.hmacSecret {
            request.setValue(EventSigner.hmacHex(secret: secret, body: body), forHTTPHeaderField: "X-GammaEngage-Signature-Content")
            request.setValue("1", forHTTPHeaderField: "X-GammaEngage-Signature-Version")
        }
        request.httpBody = Data(body.utf8)
        perform(request, what: type, completion: completion)
    }

    /// Public, unsigned endpoint: records that the notification carrying this tracking id was tapped.
    func reportOpen(trackingEventId: String) {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard
            let brand = config.brandId.addingPercentEncoding(withAllowedCharacters: allowed),
            let id = trackingEventId.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: "\(baseURL)/t/po/\(brand)/\(id)")
        else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        perform(request, what: "push open", completion: nil)
    }

    private func perform(_ request: URLRequest, what: String, completion: (@Sendable (Bool) -> Void)?) {
        transport.send(request) { [weak self] status in
            let ok = status.map { (200...299).contains($0) } ?? false
            self?.log("\(what) -> \(status.map(String.init) ?? "no response")")
            completion?(ok)
        }
    }

    private func log(_ message: String) {
        if config.debug { print("[GammaEngage] \(message)") }
    }

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
