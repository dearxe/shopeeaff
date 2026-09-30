import Foundation

protocol LinkService: Sendable {
    func create(_ request: CreateRequest, key: String) async throws -> JobResponse
    func status(jobId: String) async throws -> JobResponse
    func health() async throws -> HealthResponse
}
// Refuse every redirect, so an Authorization header can never follow a redirect.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class HTTPService: LinkService, @unchecked Sendable {
    private let base: URL
    private let auth: any AuthProvider
    private let session: URLSession
    init(base: URL, auth: any AuthProvider) {
        self.base = base
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    static func validateBase(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https", c.host != nil,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", let url = c.url else { throw ValidationError.invalidURL }
        return url
    }
    static func retryAfter(_ value: String?, now: Date = Date()) -> Double? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
    private func send<T: Decodable>(_ path: [String], method: String = "GET", body: Data? = nil,
                                    key: String? = nil, type: T.Type) async throws -> (T, Double?) {
        let url = path.reduce(base) { $0.appendingPathComponent($1) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if let authorization = try auth.authorization() { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw ServiceError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        let retry = Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"))
        if http.statusCode == 401 || http.statusCode == 403 { throw ServiceError.unauthorized }
        if http.statusCode == 429 { throw ServiceError.rateLimited(retry ?? 10) }
        let validCodes = method == "POST" ? [200, 202] : [200]
        guard validCodes.contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw ServiceError.server(envelope?.error.message ?? "Backend ตอบ HTTP \(http.statusCode)", envelope?.error.retryable ?? (http.statusCode >= 500), retry)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw ServiceError.invalidResponse }
            return date
        }
        do { return (try decoder.decode(T.self, from: data), retry) }
        catch { throw ServiceError.invalidResponse }
    }
    private struct ErrorEnvelope: Decodable { let error: APIErrorBody }
    private func merge(_ job: JobResponse, retry: Double?) -> JobResponse {
        JobResponse(jobId: job.jobId, status: job.status, originalUrl: job.originalUrl,
                    affiliateUrl: job.affiliateUrl, createdAt: job.createdAt, updatedAt: job.updatedAt,
                    retryAfterSeconds: [job.retryAfterSeconds, retry].compactMap { $0 }.max(), error: job.error)
    }
    func create(_ request: CreateRequest, key: String) async throws -> JobResponse {
        let (job, retry) = try await send(["v1", "link-jobs"], method: "POST", body: JSONEncoder().encode(request), key: key, type: JobResponse.self)
        guard job.jobId.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw ServiceError.invalidResponse
        }
        return merge(job, retry: retry)
    }
    func status(jobId: String) async throws -> JobResponse {
        guard jobId.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw ServiceError.invalidResponse }
        let (job, retry) = try await send(["v1", "link-jobs", jobId], type: JobResponse.self)
        return merge(job, retry: retry)
    }
    func health() async throws -> HealthResponse { try await send(["v1", "health"], type: HealthResponse.self).0 }
}
