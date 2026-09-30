import Foundation

struct URLValidator {
    let allowedHosts: [String]
    func validate(_ text: String) throws -> URL {
        guard let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased(),
              allowedHosts.map({ $0.lowercased() }).contains(host),
              components.port == nil || components.port == 443,
              let url = components.url else { throw ValidationError.invalidURL }
        return url
    }
    func extract(_ text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A direct URL is validated without detector normalization, preserving its query.
        if !trimmed.contains(where: { $0.isWhitespace }), trimmed.contains("://") {
            return try validate(trimmed)
        }
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        guard matches.count == 1 else {
            throw matches.isEmpty ? ValidationError.invalidURL : ValidationError.multipleURLs
        }
        guard let range = Range(matches[0].range, in: trimmed) else { throw ValidationError.invalidURL }
        return try validate(String(trimmed[range]))
    }
    func validateResponse(_ job: JobResponse, originalURL: String, jobId: String? = nil) throws {
        guard !job.jobId.isEmpty, job.originalUrl == originalURL,
              jobId == nil || job.jobId == jobId,
              job.updatedAt >= job.createdAt,
              job.retryAfterSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw ServiceError.invalidResponse
        }
        if job.status == .completed {
            guard let result = job.affiliateUrl, (try? validate(result)) != nil, job.error == nil else {
                throw ServiceError.invalidResponse
            }
        } else if job.affiliateUrl != nil {
            throw ServiceError.invalidResponse
        }
        if job.status == .failed && job.error == nil { throw ServiceError.invalidResponse }
    }
}
enum ValidationError: Error, LocalizedError {
    case invalidURL, multipleURLs
    var errorDescription: String? {
        switch self {
        case .invalidURL: "กรุณาวางลิงก์ HTTPS ของโดเมน Shopee ที่อนุญาต โดยไม่มีชื่อผู้ใช้หรือรหัสผ่านใน URL"
        case .multipleURLs: "พบหลายลิงก์ กรุณาวางครั้งละหนึ่งลิงก์"
        }
    }
}
