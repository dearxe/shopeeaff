import SwiftUI
import UIKit

struct MockBanner: View {
    var body: some View {
        Label("โหมดจำลอง — ไม่ใช่ลิงก์ Affiliate จริง", systemImage: "testtube.2")
            .font(.callout).foregroundStyle(.orange).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("mock-banner")
    }
}
struct RootView: View {
    @Bindable var model: AppModel
    var body: some View {
        TabView {
            CreateView(model: model).tabItem { Label("สร้างลิงก์", systemImage: "link.badge.plus") }
            HistoryView(model: model).tabItem { Label("ประวัติ", systemImage: "clock") }
            SettingsView(model: model).tabItem { Label("ตั้งค่า", systemImage: "gearshape") }
        }
        .alert(Brand.name, isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("ตกลง", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}
struct CreateView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.settings.mock { MockBanner() }
                    HStack(spacing: 12) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AFFILIATE").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(Brand.accent)
                            Text("Link Helper").font(.title2.weight(.semibold))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("เปลี่ยนลิงก์สินค้า\nให้พร้อมแชร์").font(.largeTitle.bold())
                        Text("วางลิงก์ Shopee แล้วให้ระบบสร้างลิงก์ Affiliate ให้คุณ").foregroundStyle(.secondary)
                    }
                    TextField("วางลิงก์สินค้าหรือข้อความแชร์", text: $model.input, axis: .vertical)
                        .lineLimit(3...6).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("url-input")
                    HStack {
                        Button { model.input = UIPasteboard.general.string ?? "" } label: { Label("วาง", systemImage: "doc.on.clipboard") }
                        Spacer()
                        Button("ล้างข้อความ") { model.input = "" }.disabled(model.input.isEmpty)
                    }
                    Picker("ช่องทางที่จะนำลิงก์ไปแชร์", selection: $model.channel) {
                        ForEach(ShareChannel.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu)
                    Text("เลือกช่องทางเพื่อให้ Backend จัดข้อมูลติดตาม จากนั้นใช้ปุ่มแชร์หรือคัดลอกไปวางในแอปที่ต้องการ")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { model.submit() } label: {
                        HStack {
                            if model.submitting { ProgressView() }
                            Text(model.submitting ? "กำลังส่งคำขอ" : "สร้างลิงก์ Affiliate").font(.headline)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.submitting)
                        .accessibilityIdentifier("submit-button")
                    Text(model.connection).font(.callout).foregroundStyle(.secondary)
                    if let job = model.selected { JobCard(model: model, job: job) }
                    else { ContentUnavailableView("พร้อมสร้างลิงก์", systemImage: "link", description: Text("ผลลัพธ์จะปรากฏที่นี่ และบันทึกไว้ในประวัติ")) }
                    Text("เจ้าของระบบอาจได้รับค่าคอมมิชชันจากการซื้อที่เข้าเงื่อนไข").font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("สร้างลิงก์").navigationBarTitleDisplayMode(.inline)
        }
    }
}
struct JobCard: View {
    let model: AppModel
    let job: LocalJob
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(job.response?.status.title ?? "ยังไม่ทราบว่า Backend รับคำขอแล้วหรือไม่", systemImage: job.response?.status == .completed ? "checkmark.circle.fill" : "clock")
                .font(.headline)
            Text(job.request.originalUrl).font(.callout).textSelection(.enabled)
            Text(job.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            if let tracking = job.request.tracking {
                Text("ช่องทาง: \(tracking.channel.title)").font(.caption).foregroundStyle(.secondary)
            }
            if let response = job.response {
                Text("Job ID: \(response.jobId)").font(.caption).textSelection(.enabled)
                if response.status == .waitingForOperator { Text("ผู้ดูแลอาจต้องเข้าสู่ระบบหรือยืนยันตัวตนที่ PC กรุณารอ ไม่ต้องกรอก OTP หรือ CAPTCHA ในแอปนี้").font(.callout) }
                if let error = response.error { Text(error.message).foregroundStyle(.red) }
                if response.status == .completed, let link = response.affiliateUrl, let url = try? model.validator.validate(link) {
                    Text(job.isMock ? "ตัวอย่างลิงก์จำลอง" : "ลิงก์ Affiliate").font(.headline)
                    Text(link).textSelection(.enabled).font(.callout)
                    ViewThatFits(in: .horizontal) {
                        HStack { actions(url) }
                        VStack(alignment: .leading) { actions(url) }
                    }
                    if copied { Text("คัดลอกแล้ว").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if job.response == nil || !(job.response?.status.terminal ?? false) {
                Button(job.response == nil ? "ส่งคำขอเดิมอีกครั้ง (ใช้ key เดิม)" : "ตรวจสถานะอีกครั้ง") { model.checkAgain(job.id) }
                    .disabled(model.submitting)
            }
            if job.response?.status == .failed {
                Button("สร้างงานใหม่จากลิงก์นี้") {
                    model.input = job.request.originalUrl
                    if let channel = job.request.tracking?.channel { model.channel = channel }
                    model.submit()
                }
                    .disabled(model.submitting)
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
    @ViewBuilder private func actions(_ url: URL) -> some View {
        Button { UIPasteboard.general.string = url.absoluteString; copied = true } label: { Label("คัดลอก", systemImage: "doc.on.doc") }
        ShareLink(item: job.isMock ? "โหมดจำลอง — ไม่ใช่ลิงก์ Affiliate จริง\n\(url.absoluteString)" : url.absoluteString) { Label("แชร์", systemImage: "square.and.arrow.up") }
        Button { if !job.isMock, (try? model.validator.validate(url.absoluteString)) != nil { openURL(url) } } label: { Label("เปิดสินค้า", systemImage: "arrow.up.right.square") }
            .disabled(job.isMock)
    }
}
struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var confirmDeleteAll = false
    var body: some View {
        NavigationStack {
            List {
                if model.settings.mock { MockBanner().listRowSeparator(.hidden) }
                Section {
                    if model.visibleJobs.isEmpty { ContentUnavailableView("ยังไม่มีประวัติ", systemImage: "clock", description: Text("งานที่สร้างในโหมดและบัญชีนี้จะปรากฏที่นี่")) }
                    ForEach(model.visibleJobs) { job in
                        NavigationLink {
                            ScrollView {
                                VStack(spacing: 16) {
                                    if job.isMock { MockBanner() }
                                    // Look up current record so polling updates the detail screen.
                                    if let current = model.visibleJobs.first(where: { $0.id == job.id }) { JobCard(model: model, job: current) }
                                    Text(model.connection).font(.caption).foregroundStyle(.secondary)
                                }.padding()
                            }.navigationTitle("รายละเอียดงาน")
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.response?.status.title ?? "คำขอรอตรวจสอบ").font(.headline)
                                Text(job.request.originalUrl).lineLimit(2).font(.callout).foregroundStyle(.secondary)
                                Text(job.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            }
                        }
                    }.onDelete { offsets in
                        let list = model.visibleJobs
                        model.delete(Set(offsets.map { list[$0].id }))
                    }
                } footer: { Text("ลบเฉพาะประวัติในเครื่อง ไม่ใช่การยกเลิกหรือลบงานบน Backend หากลบคำขอที่ยังไม่ทราบผล จะไม่สามารถ retry ด้วย key เดิมจากแอปได้") }
            }.navigationTitle("ประวัติ")
                .toolbar { Button("ลบทั้งหมด", role: .destructive) { confirmDeleteAll = true }.disabled(model.visibleJobs.isEmpty) }
                .confirmationDialog("ลบประวัติทั้งหมดของโหมดและบัญชีนี้? งานบน Backend จะยังอยู่", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                    Button("ลบประวัติในเครื่อง", role: .destructive) { model.delete(Set(model.visibleJobs.map(\.id))) }
                }
        }
    }
}
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = Settings()
    @State private var secret = ""
    @State private var hosts = ""
    var body: some View {
        NavigationStack {
            Form {
                if model.settings.mock { MockBanner() }
                Section("รูปแบบการเชื่อมต่อ") {
                    Toggle("Mock Mode", isOn: $draft.mock)
                    if draft.mock { Picker("สถานการณ์จำลอง", selection: $draft.scenario) { ForEach(MockScenario.allCases) { Text($0.title).tag($0) } } }
                    Text("การเปลี่ยนโหมดจะมีผลเมื่อกดบันทึก").font(.caption).foregroundStyle(.secondary)
                }
                Section("Backend ส่วนตัว") {
                    TextField("https://backend.example.com", text: $draft.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("รหัสใหม่ (เว้นว่างเพื่อใช้รหัสเดิม)", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("ลบรหัสเชื่อมต่อ", role: .destructive) { model.saveSettings(draft, secret: "", deleteSecret: true); resetDraft() }
                    Text("เก็บรหัสใน Keychain สำหรับต้นแบบส่วนตัว การบันทึกรหัสใหม่จะสร้างบริบทบัญชีใหม่ ประวัติเดิมจะแยกไว้").font(.caption).foregroundStyle(.secondary)
                }
                Section("โดเมนลิงก์ที่อนุญาต") {
                    TextField("หนึ่ง hostname ต่อบรรทัด", text: $hosts, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("ใช้ตรวจทั้งลิงก์ต้นฉบับและผลลัพธ์ เพิ่มเฉพาะโดเมนที่เชื่อถือได้").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("บันทึกการตั้งค่า") {
                        draft.allowedHosts = hosts.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        model.saveSettings(draft, secret: secret)
                        resetDraft()
                    }
                    Button("ทดสอบการเชื่อมต่อที่บันทึกไว้") { model.testHealth() }.disabled(model.testingHealth)
                    if let result = model.healthMessage { Text(result).font(.callout) }
                    Text("API ติดต่อได้ ไม่ได้แปลว่า Bot พร้อมทำงาน").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("เจ้าของระบบอาจได้รับค่าคอมมิชชันจากการซื้อที่เข้าเงื่อนไข")
                    Text("ตรวจสถานะเฉพาะเมื่อเปิดแอปอยู่ กลับมาเปิดแอปเพื่อตรวจต่อ ไม่มี push notification ในเวอร์ชันนี้")
                }.font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("ตั้งค่า").onAppear { resetDraft() }
        }
    }
    private func resetDraft() { draft = model.settings; secret = ""; hosts = draft.allowedHosts.joined(separator: "\n") }
}
