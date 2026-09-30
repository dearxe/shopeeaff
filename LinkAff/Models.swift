import Foundation

enum JobStatus: String, Codable, CaseIterable, Sendable {
    case queued, processing, waitingForOperator = "waiting_for_operator", completed, failed
    var terminal: Bool { self == .completed || self == .failed }
    var title: String {
        switch self {
        case .queued: "รอคิว"
        case .processing: "กำลังสร้างลิงก์"
        case .waitingForOperator: "รอผู้ดูแลดำเนินการ"
        case .completed: "สำเร็จ"
        case .failed: "ไม่สำเร็จ"
        }
    }
}
struct APIErrorBody: Codable, Sendable {
    let code: String
    let message: String
    let retryable: Bool
}
struct JobResponse: Codable, Sendable {
    let jobId: String
    let status: JobStatus
    let originalUrl: String
    let affiliateUrl: String?
    let createdAt: Date
    let updatedAt: Date
    let retryAfterSeconds: Double?
    let error: APIErrorBody?
}
struct CreateRequest: Codable, Equatable, Sendable {
    let clientRequestId: String
    let originalUrl: String
    let tracking: TrackingRequest?
    init(clientRequestId: String, originalUrl: String, tracking: TrackingRequest? = nil) {
        self.clientRequestId = clientRequestId
        self.originalUrl = originalUrl
        self.tracking = tracking
    }
}
struct HealthResponse: Codable, Sendable {
    let apiStatus: String
    let workerStatus: String
}
enum MockScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    case success, operatorWait, failed, offline, timeout, unauthorized, rateLimit, malformed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .success: "สำเร็จตามปกติ"
        case .operatorWait: "รอผู้ดูแล แล้วสำเร็จ"
        case .failed: "งานล้มเหลว"
        case .offline: "เซิร์ฟเวอร์ออฟไลน์"
        case .timeout: "POST timeout หลังรับงาน"
        case .unauthorized: "รหัสเชื่อมต่อไม่ถูกต้อง"
        case .rateLimit: "จำกัดจำนวนคำขอ"
        case .malformed: "Response ผิดรูปแบบ"
        }
    }
}
struct Settings: Codable, Equatable {
    var mock = true
    var baseURL = "https://backend.example.com"
    var accountScope = UUID().uuidString
    var scenario = MockScenario.success
    var allowedHosts = ["shopee.co.th", "www.shopee.co.th", "s.shopee.co.th", "shope.ee"]
    var environment: String { mock ? "mock:\(scenario.rawValue)" : "http:\(baseURL):\(accountScope)" }
}
struct LocalJob: Codable, Identifiable {
    var id: String { request.clientRequestId }
    let environment: String
    let isMock: Bool
    let request: CreateRequest
    let idempotencyKey: String
    var response: JobResponse?
    let savedAt: Date
    var nextAttemptAt: Date? = nil
}
enum ServiceError: Error, LocalizedError {
    case transport(String), unauthorized, rateLimited(Double), invalidResponse, server(String, Bool, Double? = nil)
    var errorDescription: String? {
        switch self {
        case .transport(let message): "เชื่อมต่อไม่ได้: \(message) งานบนเซิร์ฟเวอร์อาจยังดำเนินอยู่"
        case .unauthorized: "ไม่มีสิทธิ์เข้าถึง กรุณาตรวจรหัสเชื่อมต่อ"
        case .rateLimited: "ส่งคำขอบ่อยเกินไป กรุณารอแล้วตรวจอีกครั้ง"
        case .invalidResponse: "ข้อมูลตอบกลับไม่ถูกต้อง กรุณาตรวจสถานะอีกครั้งหรือติดต่อผู้ดูแล"
        case .server(let message, _, _): message
        }
    }
    var retryable: Bool {
        switch self {
        case .transport, .rateLimited: true
        case .server(_, let retryable, _): retryable
        default: false
        }
    }
    var retryAfterSeconds: Double? {
        switch self {
        case .rateLimited(let seconds): seconds
        case .server(_, _, let seconds): seconds
        default: nil
        }
    }
}
