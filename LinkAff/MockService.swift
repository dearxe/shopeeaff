import Foundation

actor MockService: LinkService {
    let scenario: MockScenario
    private var records: [String: CreateRequest] = [:]
    private var rateLimited = false
    init(scenario: MockScenario) { self.scenario = scenario }
    private func check() throws {
        switch scenario {
        case .offline: throw ServiceError.transport("เซิร์ฟเวอร์จำลองออฟไลน์")
        case .unauthorized: throw ServiceError.unauthorized
        case .rateLimit where !rateLimited:
            rateLimited = true
            throw ServiceError.rateLimited(5)
        case .malformed: throw ServiceError.invalidResponse
        default: break
        }
    }
    func create(_ request: CreateRequest, key: String) async throws -> JobResponse {
        try check()
        if let old = records[key], old != request { throw ServiceError.server("Idempotency conflict", false) }
        records[key] = request
        let defaults = UserDefaults.standard
        let timingKey = "mock-start-\(request.clientRequestId)"
        if defaults.double(forKey: timingKey) == 0 { defaults.set(Date().timeIntervalSince1970, forKey: timingKey) }
        if scenario == .timeout && !defaults.bool(forKey: "mock-timeout-\(key)") {
            defaults.set(true, forKey: "mock-timeout-\(key)")
            throw ServiceError.transport("จำลอง timeout หลัง Backend รับงานแล้ว")
        }
        return response(request: request, jobId: try makeId(request), stage: 0)
    }
    // Embed the original request in a demo-only id so GET survives a process restart.
    private func makeId(_ request: CreateRequest) throws -> String {
        "demo." + (try JSONEncoder().encode(request)).base64EncodedString()
    }
    func status(jobId: String) async throws -> JobResponse {
        try check()
        guard jobId.hasPrefix("demo."), let data = Data(base64Encoded: String(jobId.dropFirst(5))),
              let request = try? JSONDecoder().decode(CreateRequest.self, from: data) else { throw ServiceError.invalidResponse }
        // Persist demo timing so checking the same job after relaunch continues the flow.
        let defaults = UserDefaults.standard
        let timingKey = "mock-start-\(request.clientRequestId)"
        let started = defaults.double(forKey: timingKey)
        let now = Date().timeIntervalSince1970
        if started == 0 { defaults.set(now, forKey: timingKey) }
        let elapsed = started == 0 ? 0 : now - started
        return response(request: request, jobId: jobId, stage: elapsed < 3 ? 1 : elapsed < 8 ? 2 : 3)
    }
    private func response(request: CreateRequest, jobId: String, stage: Int) -> JobResponse {
        let status: JobStatus
        if stage == 0 { status = .queued }
        else if scenario == .failed { status = .failed }
        else if scenario == .operatorWait && stage == 1 { status = .waitingForOperator }
        else { status = stage >= 3 ? .completed : .processing }
        let now = Date()
        let timestamp = UserDefaults.standard.double(forKey: "mock-start-\(request.clientRequestId)")
        let created = timestamp == 0 ? now : Date(timeIntervalSince1970: timestamp)
        return JobResponse(jobId: jobId, status: status, originalUrl: request.originalUrl,
                           affiliateUrl: status == .completed ? "https://shopee.co.th/?linkaff_demo=not_an_affiliate_link" : nil,
                           createdAt: created, updatedAt: now,
                           retryAfterSeconds: status == .waitingForOperator ? 10 : 2,
                           error: status == .failed ? APIErrorBody(code: "DEMO_FAILED", message: "งานจำลองไม่สำเร็จ", retryable: false) : nil)
    }
    func health() async throws -> HealthResponse {
        try check()
        return HealthResponse(apiStatus: "ok", workerStatus: scenario == .operatorWait ? "needs_attention" : "ready")
    }
}
