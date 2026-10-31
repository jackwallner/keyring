import Network
import XCTest
@testable import Keyring

/// api.nhtsa.gov answers with no cache headers, and `NHTSAClient.session` hands back its cached copy whenever it
/// has one, so the first recall list a vehicle got would be the only one it ever saw.
final class RecallFreshnessTests: XCTestCase {
    func testALaterLookUpForTheSameVehicleReachesTheServer() async throws {
        let server = try RecallServer()
        defer { server.stop() }
        let first = try await NHTSAClient.recalls(year: 2019, make: "Toyota", model: "Tacoma", endpoint: server.url)
        let second = try await NHTSAClient.recalls(year: 2019, make: "Toyota", model: "Tacoma", endpoint: server.url)
        XCTAssertEqual(first.map(\.campaign), ["24V000001"])
        XCTAssertEqual(second.map(\.campaign), ["24V000002"], "the second look got the first answer back from the cache")
        XCTAssertEqual(server.requests, 2)
    }

    func testTheRequestAsksForTheVehicleBeingChecked() {
        let request = NHTSAClient.recallsRequest(year: 2019, make: "Toyota", model: "Tacoma")
        XCTAssertEqual(request.url?.host, "api.nhtsa.gov")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "make" }?.value, "Toyota")
        XCTAssertEqual(items.first { $0.name == "model" }?.value, "Tacoma")
        XCTAssertEqual(items.first { $0.name == "modelYear" }?.value, "2019")
    }
}

/// A local stand-in for api.nhtsa.gov, with the headers it sends: no Cache-Control, Expires, ETag or Last-Modified.
/// Every answer names a new campaign, so a repeated answer can only have come from a cache.
private final class RecallServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "recall-server")
    private let lock = NSLock()
    private var count = 0
    private(set) var url = URL(string: "http://127.0.0.1")!

    var requests: Int { lock.withLock { count } }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [unowned self] connection in self.serve(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success, let port = listener.port else { throw URLError(.cannotConnectToHost) }
        url = URL(string: "http://127.0.0.1:\(port.rawValue)/recalls/recallsByVehicle")!
    }

    func stop() { listener.cancel() }

    private func serve(_ accepted: NWConnection) {
        nonisolated(unsafe) let connection = accepted
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [self] data, _, _, _ in
            guard data != nil else { return connection.cancel() }
            let number = lock.withLock { () -> Int in
                count += 1
                return count
            }
            let body = Data(#"{"Count":1,"results":[{"NHTSACampaignNumber":"24V00000\#(number)","Component":"SERVICE BRAKES","Summary":"s","Consequence":"c","Remedy":"r","ReportReceivedDate":"01/02/2024","parkIt":false,"parkOutSide":false}]}"#.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json;charset=UTF-8\r\nContent-Language: en-US\r\nVary: Origin\r\nVary: Access-Control-Request-Method\r\nVary: Access-Control-Request-Headers\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
