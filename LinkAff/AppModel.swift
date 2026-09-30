import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var settings = Settings()
    private(set) var jobs: [LocalJob] = []
    var input = ""
    var channel = ShareChannel.tiktok
    var selectedID: String?
    private(set) var submitting = false
    private(set) var connection = "พร้อมใช้งาน"
    var message: String?
    private(set) var healthMessage: String?
    private(set) var testingHealth = false
    private var service: any LinkService
    private let store: LocalStore
    private var pollTask: Task<Void, Never>?
    private var submitTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var foreground = false
    private var generation = 0
    private var notBefore: [String: Date] = [:]
    private var intervals: [String: Double] = [:]
    var visibleJobs: [LocalJob] { jobs.filter { $0.environment == settings.environment }.sorted { $0.savedAt > $1.savedAt } }
    var selected: LocalJob? { visibleJobs.first { $0.id == selectedID } }
    var validator: URLValidator { URLValidator(allowedHosts: settings.allowedHosts) }
    var hasUncertainSubmission: Bool { visibleJobs.contains { $0.response == nil } }

    init(store: LocalStore? = nil, service: (any LinkService)? = nil) {
        let storage = store ?? LocalStore()
        self.store = storage
        self.service = service ?? MockService(scenario: .success)
        do {
            settings = try storage.read(Settings.self, name: "settings.json", fallback: Settings())
            jobs = try storage.read([LocalJob].self, name: "jobs.json", fallback: [])
            for job in jobs { notBefore[job.id] = job.nextAttemptAt }
            if service == nil { self.service = Self.makeService(settings) }
            selectedID = visibleJobs.first?.id
        } catch {
            message = "อ่านข้อมูลในเครื่องไม่ได้: \(error.localizedDescription) กรุณาตรวจไฟล์ก่อนส่งงานใหม่"
            storageUsable = false
        }
    }
    private var storageUsable = true
    private static func makeService(_ settings: Settings) -> any LinkService {
        if settings.mock { return MockService(scenario: settings.scenario) }
        // Settings are validated before saving; invalid saved data remains an explicit error service.
        guard let base = try? HTTPService.validateBase(settings.baseURL) else { return UnconfiguredService() }
        return HTTPService(base: base, auth: KeychainAuthProvider(account: settings.accountScope))
    }
    private func persistJobs() throws { try store.write(jobs, name: "jobs.json") }
    func setForeground(_ value: Bool) {
        foreground = value
        pollTask?.cancel()
        pollTask = nil
        if value {
            for job in visibleJobs where job.response != nil && notBefore[job.id] == nil {
                notBefore[job.id] = Date().addingTimeInterval(max(2, job.response?.retryAfterSeconds ?? 0))
            }
            startPolling()
        }
        else { connection = "พักตรวจสถานะขณะแอปอยู่เบื้องหลัง" }
    }
    func submit() {
        guard !submitting, storageUsable else { return }
        do {
            let url = try validator.extract(input)
            guard !hasUncertainSubmission else {
                message = "มีคำขอที่ยังไม่ทราบผล กรุณาตรวจคำขอเดิมจากประวัติก่อนสร้างงานใหม่"
                return
            }
            let request = CreateRequest(clientRequestId: UUID().uuidString, originalUrl: url.absoluteString,
                                        tracking: TrackingRequest(channel: channel, subIdPrefixes: Brand.subIDPrefixes))
            let job = LocalJob(environment: settings.environment, isMock: settings.mock, request: request,
                               idempotencyKey: UUID().uuidString, response: nil, savedAt: Date())
            jobs.append(job)
            do { try persistJobs() } catch { jobs.removeAll { $0.id == job.id }; throw error }
            selectedID = job.id
            beginSubmit(job)
        } catch { message = error.localizedDescription }
    }
    private func beginSubmit(_ job: LocalJob) {
        guard !submitting, job.environment == settings.environment, job.response == nil else { return }
        if let date = notBefore[job.id], date != .distantFuture, date > Date() {
            message = "กรุณารอถึง \(date.formatted(date: .omitted, time: .standard)) แล้วลองอีกครั้ง"
            return
        }
        submitting = true
        message = nil
        connection = "กำลังส่งคำขอ"
        let revision = generation
        let activeService = service
        submitTask = Task { [weak self] in
            do {
                let response = try await activeService.create(job.request, key: job.idempotencyKey)
                guard let self, self.generation == revision, !Task.isCancelled else { return }
                try self.accept(response, for: job)
                self.connection = "เชื่อมต่อแล้ว"
            } catch {
                guard let self, self.generation == revision, !Task.isCancelled else { return }
                self.handle(error, for: job.id)
            }
            guard let self, self.generation == revision else { return }
            self.submitting = false
            self.startPolling()
        }
    }
    func checkAgain(_ id: String) {
        guard let job = visibleJobs.first(where: { $0.id == id }) else { return }
        selectedID = id
        if job.response == nil { beginSubmit(job); return }
        guard foreground, !(job.response?.status.terminal ?? false) else { return }
        if let date = notBefore[id], date != .distantFuture, date > Date() {
            message = "Backend ขอให้รอถึง \(date.formatted(date: .omitted, time: .standard))"
            return
        }
        pollTask?.cancel()
        notBefore[id] = .distantPast
        startPolling()
    }
    private func accept(_ response: JobResponse, for job: LocalJob) throws {
        try validator.validateResponse(response, originalURL: job.request.originalUrl, jobId: job.response?.jobId)
        if let previous = job.response {
            guard response.createdAt == previous.createdAt, response.updatedAt >= previous.updatedAt else {
                throw ServiceError.invalidResponse
            }
        }
        guard let index = jobs.firstIndex(where: { $0.id == job.id && $0.environment == settings.environment }) else { return }
        let interval = intervals[job.id] ?? 2
        let delay = max(response.retryAfterSeconds ?? 0, response.status == .waitingForOperator ? 30 : interval)
        let nextAttempt = Date().addingTimeInterval(delay)
        let previous = jobs[index]
        jobs[index].response = response
        jobs[index].nextAttemptAt = nextAttempt
        do { try persistJobs() } catch { jobs[index] = previous; throw error }
        intervals[job.id] = min(10, interval * 1.5)
        notBefore[job.id] = nextAttempt
    }
    private func handle(_ error: Error, for id: String) {
        message = error.localizedDescription
        connection = "ตรวจสถานะการเชื่อมต่อไม่สำเร็จ"
        if let delay = (error as? ServiceError)?.retryAfterSeconds {
            notBefore[id] = Date().addingTimeInterval(max(2, delay))
        } else {
            let delay = min(10, (intervals[id] ?? 2) * 1.5)
            intervals[id] = delay
            // Non-retryable connection/response failures pause until manual retry.
            notBefore[id] = (error as? ServiceError)?.retryable == true ? Date().addingTimeInterval(delay) : .distantFuture
        }
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].nextAttemptAt = notBefore[id]
            do { try persistJobs() } catch { message = "บันทึกเวลาตรวจครั้งถัดไปไม่ได้: \(error.localizedDescription)" }
        }
    }
    private func startPolling() {
        guard foreground else { return }
        pollTask?.cancel()
        let revision = generation
        let activeService = service
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.foreground, self.generation == revision else { return }
                let candidates = self.visibleJobs.filter { $0.response != nil && !($0.response!.status.terminal) }
                guard !candidates.isEmpty else { return }
                for job in candidates {
                    guard !Task.isCancelled, self.generation == revision else { return }
                    guard (self.notBefore[job.id] ?? .distantPast) <= Date() else { continue }
                    do {
                        let response = try await activeService.status(jobId: job.response!.jobId)
                        guard !Task.isCancelled, self.generation == revision else { return }
                        // Deletion during an in-flight GET never resurrects a local record.
                        try self.accept(response, for: job)
                        self.connection = "เชื่อมต่อแล้ว"
                    } catch {
                        guard !Task.isCancelled, self.generation == revision else { return }
                        self.handle(error, for: job.id)
                    }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    func saveSettings(_ proposed: Settings, secret: String, deleteSecret: Bool = false) {
        do {
            var next = proposed
            let base = try HTTPService.validateBase(next.baseURL)
            next.baseURL = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let hosts = next.allowedHosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard !hosts.isEmpty, hosts.allSatisfy({ !$0.isEmpty && !$0.contains(":") && !$0.contains("/") && !$0.contains(" ") }) else {
                throw ValidationError.invalidURL
            }
            next.allowedHosts = Array(Set(hosts)).sorted()
            let changesAuth = !secret.isEmpty || deleteSecret
            if changesAuth { next.accountScope = UUID().uuidString }
            if !secret.isEmpty {
                guard !secret.contains(where: { $0.isNewline || $0.asciiValue.map({ $0 < 32 }) == true }) else { throw ServiceError.unauthorized }
                try KeychainAuthProvider(account: next.accountScope).save(secret)
            }
            do { try store.write(next, name: "settings.json") }
            catch {
                if !secret.isEmpty { try? KeychainAuthProvider(account: next.accountScope).delete() }
                throw error
            }
            generation += 1
            pollTask?.cancel()
            submitTask?.cancel()
            healthTask?.cancel()
            submitting = false
            testingHealth = false
            let oldScope = settings.accountScope
            settings = next
            service = Self.makeService(next)
            selectedID = visibleJobs.first?.id
            healthMessage = nil
            message = nil
            connection = "พร้อมใช้งาน"
            startPolling()
            if changesAuth {
                do { try KeychainAuthProvider(account: oldScope).delete() }
                catch { message = "บันทึกการตั้งค่าใหม่แล้ว แต่ลบรหัสเก่าใน Keychain ไม่ได้: \(error.localizedDescription)" }
            }
        } catch { message = "บันทึกตั้งค่าไม่ได้: \(error.localizedDescription)" }
    }
    func testHealth() {
        guard !testingHealth else { return }
        testingHealth = true
        healthMessage = "กำลังทดสอบ"
        let activeService = service
        let revision = generation
        healthTask = Task { [weak self] in
            do {
                let result = try await activeService.health()
                guard let self, self.generation == revision, !Task.isCancelled else { return }
                self.healthMessage = "API: \(result.apiStatus) • Bot: \(result.workerStatus)"
            } catch {
                guard let self, self.generation == revision, !Task.isCancelled else { return }
                self.healthMessage = error.localizedDescription
            }
            guard let self, self.generation == revision else { return }
            self.testingHealth = false
        }
    }
    func delete(_ ids: Set<String>) {
        let old = jobs
        jobs.removeAll { $0.environment == settings.environment && ids.contains($0.id) }
        do { try persistJobs() } catch { jobs = old; message = error.localizedDescription }
        if ids.contains(selectedID ?? "") { selectedID = nil }
        startPolling()
    }
}
private struct UnconfiguredService: LinkService {
    func create(_ request: CreateRequest, key: String) async throws -> JobResponse { throw ValidationError.invalidURL }
    func status(jobId: String) async throws -> JobResponse { throw ValidationError.invalidURL }
    func health() async throws -> HealthResponse { throw ValidationError.invalidURL }
}
