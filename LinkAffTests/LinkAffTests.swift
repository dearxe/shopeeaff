import XCTest
@testable import LinkAff

final class URLValidatorTests: XCTestCase {
    let validator = URLValidator(allowedHosts: Settings().allowedHosts)
    func testAllowedURLsAndQueryPreservation() throws {
        for host in Settings().allowedHosts {
            let text = "https://\(host)/product?a=1&b=two%20words"
            XCTAssertEqual(try validator.extract(text).absoluteString, text)
        }
        XCTAssertEqual(try validator.extract("ซื้อสินค้านี้ https://shope.ee/abcd เลย").host, "shope.ee")
    }
    func testSpoofedAndUnsafeURLs() {
        for url in ["http://shopee.co.th/x", "https://shopee.co.th.evil.com/x", "https://evilshopee.co.th/x",
                    "https://user:pass@shopee.co.th/x", "https://shopee.co.th@evil.com/x",
                    "https://shopee.co.th:8443/x", "javascript:alert(1)", "https://shopee.co.th./x"] {
            XCTAssertThrowsError(try validator.extract(url), url)
        }
        XCTAssertThrowsError(try validator.extract("https://shope.ee/one https://shope.ee/two"))
    }
    func testCompletedRequiresSafeAffiliateURL() {
        let now = Date()
        for url in [nil, "https://evil.com/x", "http://shope.ee/x"] as [String?] {
            let job = JobResponse(jobId: "job-1", status: .completed, originalUrl: "https://shope.ee/a", affiliateUrl: url,
                                  createdAt: now, updatedAt: now, retryAfterSeconds: nil, error: nil)
            XCTAssertThrowsError(try validator.validateResponse(job, originalURL: job.originalUrl))
        }
    }
    func testBackendBaseAndRetryAfter() throws {
        XCTAssertNoThrow(try HTTPService.validateBase("https://api.example.com:9443"))
        for value in ["http://api.example.com", "https://token@api.example.com", "https://api.example.com?token=x", "https://api.example.com/v1"] {
            XCTAssertThrowsError(try HTTPService.validateBase(value))
        }
        XCTAssertEqual(HTTPService.retryAfter("60"), 60)
        XCTAssertNil(HTTPService.retryAfter("NaN"))
        XCTAssertEqual(HTTPService.retryAfter("Thu, 01 Jan 1970 00:01:00 GMT", now: Date(timeIntervalSince1970: 0)), 60)
    }
}

actor RecordingService: LinkService {
    var creates: [(CreateRequest, String)] = []
    var gets: [String] = []
    var timeoutFirst: Bool
    var completeOnGet: Bool
    var current: JobResponse?
    init(timeoutFirst: Bool = false, completeOnGet: Bool = false) {
        self.timeoutFirst = timeoutFirst; self.completeOnGet = completeOnGet
    }
    func create(_ request: CreateRequest, key: String) async throws -> JobResponse {
        creates.append((request, key))
        if timeoutFirst && creates.count == 1 { throw ServiceError.transport("timeout") }
        let date = Date()
        let job = JobResponse(jobId: "job-1", status: .queued, originalUrl: request.originalUrl, affiliateUrl: nil,
                              createdAt: date, updatedAt: date, retryAfterSeconds: 0, error: nil)
        current = job
        return job
    }
    func status(jobId: String) async throws -> JobResponse {
        gets.append(jobId)
        guard let job = current else { throw ServiceError.transport("offline") }
        if !completeOnGet { return job }
        return JobResponse(jobId: job.jobId, status: .completed, originalUrl: job.originalUrl, affiliateUrl: "https://shope.ee/result",
                           createdAt: job.createdAt, updatedAt: Date(), retryAfterSeconds: nil, error: nil)
    }
    func health() async throws -> HealthResponse { HealthResponse(apiStatus: "ok", workerStatus: "offline") }
    func counts() -> (Int, Int) { (creates.count, gets.count) }
    func requests() -> [(CreateRequest, String)] { creates }
}

@MainActor
final class LifecycleTests: XCTestCase {
    var directory: URL!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    func settle() async throws { try await Task.sleep(for: .milliseconds(150)) }
    func testTimeoutRetryKeepsKeyAndRequestAcrossRelaunch() async throws {
        let service = RecordingService(timeoutFirst: true)
        let storage = LocalStore(directory: directory)
        let first = AppModel(store: storage, service: service)
        first.input = "https://shope.ee/a"
        first.channel = .instagram
        first.submit()
        first.submit() // Double tap must not enqueue another request.
        try await settle()
        XCTAssertNil(first.visibleJobs.first?.response)
        // Retry backoff is persisted; relaunch must still respect it.
        try await Task.sleep(for: .seconds(3.1))
        let restored = AppModel(store: storage, service: service)
        restored.checkAgain(try XCTUnwrap(restored.visibleJobs.first?.id))
        try await settle()
        let requests = await service.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].0, requests[1].0)
        XCTAssertEqual(requests[0].1, requests[1].1)
        XCTAssertEqual(requests[0].0.tracking?.channel, .instagram)
        XCTAssertEqual(requests[0].0.tracking?.subIdPrefixes, ["ios", "affiliate", "shop"])
        XCTAssertEqual(restored.visibleJobs.count, 1)
    }
    func testRelaunchUsesGETAndStopsAfterCompletion() async throws {
        let service = RecordingService(completeOnGet: true)
        let storage = LocalStore(directory: directory)
        let first = AppModel(store: storage, service: service)
        first.input = "https://shope.ee/a"; first.submit()
        try await settle()
        let restored = AppModel(store: storage, service: service)
        restored.setForeground(true)
        try await Task.sleep(for: .seconds(3.2))
        XCTAssertEqual(restored.visibleJobs.first?.response?.status, .completed)
        let before = await service.counts()
        try await Task.sleep(for: .seconds(3))
        let after = await service.counts()
        XCTAssertEqual(after.0, 1)
        XCTAssertEqual(before.1, after.1)
        restored.setForeground(false)
    }
    func testBackgroundPausesAndEnvironmentSeparatesJobs() async throws {
        let service = RecordingService()
        let model = AppModel(store: LocalStore(directory: directory), service: service)
        model.input = "https://shope.ee/a"; model.submit()
        try await settle()
        model.setForeground(false)
        try await Task.sleep(for: .seconds(3))
        let counts = await service.counts()
        XCTAssertEqual(counts.1, 0)
        var next = model.settings
        next.mock = false; next.baseURL = "https://other.example.com"
        model.saveSettings(next, secret: "")
        XCTAssertTrue(model.visibleJobs.isEmpty)
        XCTAssertEqual(model.jobs.count, 1)
        next.mock = true
        model.saveSettings(next, secret: "")
        XCTAssertEqual(model.visibleJobs.count, 1)
    }
    func testOfflineDoesNotFabricateSuccess() async throws {
        let model = AppModel(store: LocalStore(directory: directory), service: MockService(scenario: .offline))
        model.input = "https://shope.ee/a"; model.submit()
        try await settle()
        XCTAssertNil(model.visibleJobs.first?.response)
        XCTAssertNotNil(model.message)
    }
    func testMockIdempotencyAndConflict() async throws {
        let service = MockService(scenario: .success)
        let request = CreateRequest(clientRequestId: UUID().uuidString, originalUrl: "https://shope.ee/a")
        let key = UUID().uuidString
        let first = try await service.create(request, key: key)
        let again = try await service.create(request, key: key)
        XCTAssertEqual(first.jobId, again.jobId)
        do {
            _ = try await service.create(CreateRequest(clientRequestId: "different", originalUrl: "https://shope.ee/b"), key: key)
            XCTFail("Expected conflict")
        } catch { XCTAssertTrue(error is ServiceError) }
    }
    func testMockOperatorTransitionAndResume() async throws {
        let request = CreateRequest(clientRequestId: UUID().uuidString, originalUrl: "https://shope.ee/a")
        let timingKey = "mock-start-\(request.clientRequestId)"
        defer { UserDefaults.standard.removeObject(forKey: timingKey) }
        let service = MockService(scenario: .operatorWait)
        let queued = try await service.create(request, key: UUID().uuidString)
        XCTAssertEqual(queued.status, .queued)
        let waiting = try await service.status(jobId: queued.jobId)
        XCTAssertEqual(waiting.status, .waitingForOperator)
        UserDefaults.standard.set(Date().addingTimeInterval(-5).timeIntervalSince1970, forKey: timingKey)
        let resumed = MockService(scenario: .operatorWait)
        let processing = try await resumed.status(jobId: queued.jobId)
        XCTAssertEqual(processing.status, .processing)
        UserDefaults.standard.set(Date().addingTimeInterval(-9).timeIntervalSince1970, forKey: timingKey)
        let completed = try await resumed.status(jobId: queued.jobId)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertNotNil(completed.affiliateUrl)
    }
    func testLegacyRequestDecodesWithoutTracking() throws {
        let data = Data(#"{"clientRequestId":"old-request","originalUrl":"https://shope.ee/a"}"#.utf8)
        let request = try JSONDecoder().decode(CreateRequest.self, from: data)
        XCTAssertNil(request.tracking)
        XCTAssertEqual(request.originalUrl, "https://shope.ee/a")
    }
}
