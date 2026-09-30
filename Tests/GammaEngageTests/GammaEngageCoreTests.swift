import Foundation
import Testing
@testable import GammaEngage

private final class FakeTransport: Transport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var status: Int? = 202
    /// When true, requests stay in flight until `completeAll()`.
    var hold = false
    private var pending: [@Sendable (Int?) -> Void] = []

    func send(_ request: URLRequest, completion: @escaping @Sendable (Int?) -> Void) {
        requests.append(request)
        if hold { pending.append(completion) } else { completion(status) }
    }

    func completeAll() {
        let all = pending
        pending = []
        all.forEach { $0(status) }
    }

    func body(_ index: Int) -> String { String(decoding: requests[index].httpBody ?? Data(), as: UTF8.self) }

    func eventTypes() -> [String] {
        requests.compactMap { req in
            guard let data = req.httpBody,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json["event_type"] as? String
        }
    }
}

final class GammaEngageCoreTests {
    private let suite = "test-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let transport = FakeTransport()
    private let config = GammaEngageConfig(baseURL: "https://api.test/", brandId: "brand-1", apiKey: "key-1", hmacSecret: "secret-1")

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeCore() -> GammaEngageCore {
        GammaEngageCore(config: config, defaults: defaults, transport: transport)
    }

    @Test func registersWithSignedRequest() {
        let core = makeCore()
        core.setPlayer("p1")
        core.setPushToken("tok-1")

        #expect(transport.eventTypes() == ["push_token_registered"])
        let request = transport.requests[0]
        #expect(request.url?.absoluteString == "https://api.test/events")
        #expect(request.value(forHTTPHeaderField: "X-Tenant-API-Key") == "key-1")
        #expect(request.value(forHTTPHeaderField: "X-GammaEngage-Signature-Version") == "1")
        #expect(
            request.value(forHTTPHeaderField: "X-GammaEngage-Signature-Content")
                == EventSigner.hmacHex(secret: "secret-1", body: transport.body(0))
        )
        #expect(transport.body(0).contains("\"platform\":\"ios\""))
    }

    @Test func tokenBeforePlayerIsRememberedAndRegisteredOnLogin() {
        let core = makeCore()
        core.setPushToken("tok-1")
        #expect(transport.requests.isEmpty)
        core.setPlayer("p1")
        #expect(transport.eventTypes() == ["push_token_registered"])
    }

    @Test func duplicateRegistrationWhileInFlightIsSkipped() {
        transport.hold = true
        let core = makeCore()
        core.setPlayer("p1")
        core.setPushToken("tok-1")
        core.setPushToken("tok-1")
        #expect(transport.requests.count == 1)
        transport.completeAll()
    }

    @Test func tokenRefreshRemovesOldAndRegistersNew() {
        let core = makeCore()
        core.setPlayer("p1")
        core.setPushToken("tok-1")
        core.setPushToken("tok-2")
        #expect(transport.eventTypes() == ["push_token_registered", "push_token_removed", "push_token_registered"])
        #expect(transport.body(1).contains("tok-1"))
        #expect(transport.body(2).contains("tok-2"))
    }

    @Test func switchingPlayerUnregistersPreviousThenRegistersNew() {
        let core = makeCore()
        core.setPlayer("p1")
        core.setPushToken("tok-1")
        core.setPlayer("p2")
        #expect(transport.eventTypes() == ["push_token_registered", "push_token_removed", "push_token_registered"])
        #expect(transport.body(1).contains("\"external_player_id\":\"p1\""))
        #expect(transport.body(2).contains("\"external_player_id\":\"p2\""))
    }

    @Test func logoutUnregistersAndDoesNotReRegisterWithoutPlayer() {
        let core = makeCore()
        core.setPlayer("p1")
        core.setPushToken("tok-1")
        core.logout()
        #expect(transport.eventTypes() == ["push_token_registered", "push_token_removed"])
        core.setPushToken("tok-1")
        #expect(transport.requests.count == 2, "no player, so nothing is registered")
    }

    @Test func failedLogoutRemovalIsRetriedOnNextLaunch() {
        let core = makeCore()
        core.setPlayer("p1")
        core.setPushToken("tok-1")
        transport.status = nil
        core.logout()
        #expect(transport.requests.count == 2)

        transport.status = 202
        _ = makeCore()
        #expect(transport.eventTypes().last == "push_token_removed")
        #expect(transport.requests.count == 3)

        _ = makeCore()
        #expect(transport.requests.count == 3, "a successful retry is not repeated")
    }

    @Test func failedRegistrationIsRetriedOnTheNextToken() {
        let core = makeCore()
        core.setPlayer("p1")
        transport.status = 500
        core.setPushToken("tok-1")
        transport.status = 202
        core.setPushToken("tok-1")
        #expect(transport.eventTypes() == ["push_token_registered", "push_token_registered"])
    }

    @Test func notificationTapIsReportedOncePerTrackingId() {
        let core = makeCore()
        core.handle(userInfo: ["tracking_event_id": "trk-1", "campaign_id": "c1"])
        core.handle(userInfo: ["tracking_event_id": "trk-1"])
        core.handle(userInfo: ["other": "x"])
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].httpMethod == "GET")
        #expect(transport.requests[0].url?.absoluteString == "https://api.test/t/po/brand-1/trk-1")
    }
}
