# ผลการตรวจและแผนทดสอบ

## ผลล่าสุดจาก GitHub-hosted Mac (30 กันยายน 2026)

workflow **iOS Build and Tests** run `36672202935` ของ commit `3033316` จบด้วย `conclusion: success` ตรวจผ่าน GitHub API จริง: https://github.com/dearxe/shopeeaff/actions/runs/36672202935 workflow รัน xcodebuild test บน iPhone Simulator และตรวจ iOS SDK >=26 ก่อนเริ่ม จึงยืนยัน build และ XCTest ของ source ณ commit นี้ผ่านแล้ว

ยังไม่ได้ทดสอบ UI ด้วยมือบน Simulator, iPhone จริง, HTTP integration กับ Backend จริง, signing/archive/IPA, TestFlight หรือ App Store ข้อมูลส่วนล่างเป็นบันทึกตรวจเดิมก่อน CI รอบนี้ ข้อความว่า tests ยังไม่ได้รันในบันทึกเดิมถูกแทนด้วยผล CI ล่าสุดนี้

## ตรวจจริงในสภาพแวดล้อมนี้ (Windows, 30 กันยายน 2026)

- อ่าน workspace เดิม: มีเพียง `.git` ไม่มี source เดิมให้แก้ทับ
- ไม่มี Swift หรือ xcodebuild ใน PATH ไม่ได้รัน build, XCTest, Simulator, UI tests, signing, archive หรือ TestFlight ภายหลังพบ bundled Git executable และใช้ตรวจ working tree ได้
- รัน PowerShell generator สร้าง Xcode project จริงพร้อม app target, hosted unit-test target และ shared scheme
- รัน `scripts/Verify-Structure.ps1` ตรวจ unique/resolved PBX references, source files, scheme/manifest XML, OpenAPI component references, trailing whitespace และ source patterns ที่ไม่ควรมี
- การตรวจ OpenAPI นี้เป็น reference check ไม่ใช่ YAML parser หรือ OpenAPI validator และการตรวจ source ไม่พิสูจน์ runtime behavior
- หลังปรับแบรนด์ ตรวจผ่านเพิ่มเติม: Bundle ID ใหม่ใน project, JSON ของ asset catalogs/config, file paths ของภาพ, AppIcon 1024×1024 RGB ไม่มี alpha และ PowerShell scripts ผ่าน syntax parser
- เพิ่ม workflow macOS build/test และ signing/TestFlight แต่ยังไม่รัน GitHub Actions ไม่มีผล build/test ผ่านเพิ่ม การอ่าน YAML ตรวจ reference ไม่ใช่การยืนยัน syntax ของ workflows; ต้องตรวจกับ GitHub เมื่ออัปโหลด
- เชื่อมบัญชี dearxe ด้วย Git Credential Manager browser login และ push source/workflows ไปยัง branch codex/affiliate-helper-ios สำเร็จแล้ว ยังไม่มีผล build/tests ผ่านจาก CI

## XCTest ที่เขียนไว้ (ยังไม่ได้รัน)

|ชุดทดสอบ|ประเด็น|
|---|---|
|URLValidatorTests|allowlist ทั้ง 4 hostname, query preservation, share text, URL หลายอัน, scheme, credentials, spoofed host, port|
|URLValidatorTests|completed ไม่มี affiliateUrl หรือ URL ไม่ปลอดภัย, base origin, Retry-After seconds/date|
|LifecycleTests|double submit, timeout retry ใช้ request/key เดิมและ persisted pending หลัง relaunch|
|LifecycleTests|tracking channel/prefix คงเดิมเมื่อ retry และ request เก่าที่ไม่มี tracking ยัง decode ได้|
|LifecycleTests|relaunch ใช้ GET งานเดิม, ไม่ POST ใหม่, terminal หยุด polling|
|LifecycleTests|background ไม่ GET, สลับ environment ไม่ปนงาน, สลับกลับเห็นงานเดิม|
|LifecycleTests|offline ไม่มี fabricated completed response, Mock idempotency และ conflict|
|LifecycleTests|Mock queued → waiting_for_operator → processing → completed และ service ใหม่ตรวจ jobId เดิมได้|

รันด้วย ⌘U หรือคำสั่ง xcodebuild ใน README บน Mac หากพบ compiler/runtime failures ต้องแก้และรันใหม่ก่อนเรียกว่า build ผ่าน

## ตรวจด้วยมือบน Simulator และ iPhone จริง

1. ทดสอบครบ 8 Mock scenarios ใน settings ตรวจป้ายจำลองในทุกแท็บ/รายละเอียด, Share sheet มีข้อความจำลอง และเปิดสินค้าจำลองถูกปิด
2. ปิดแอปขณะ queued/processing แล้วเปิดใหม่ ต้อง GET เดิม; ปิดหลัง ambiguous POST แล้ว retry ต้อง POST ด้วย key เดิม
3. เข้า background ขณะ GET รออยู่ ต้องไม่รับผลหลัง cancellation หรือ poll ต่อ กลับ foreground จึงตรวจงานต่อ
4. waiting_for_operator แสดงคำอธิบาย ไม่ขอ OTP/CAPTCHA และรอตามช่วงขั้นต่ำ 30 วินาที
5. failed เท่านั้นมีปุ่มสร้างใหม่ กดแล้วใช้ UUID ใหม่ transport error ต้องไม่เปลี่ยนงานเป็น failed
6. วาง URL ที่มี username/password, `shopee.co.th.evil.com`, `evilshopee.co.th`, HTTP, query และ share text หลาย URL
7. ปรับ base URL/รหัส/โหมดระหว่างมี request ค้าง ผลเก่าต้องไม่กลับมาแทนงานใหม่; ประวัติใหม่แยก scope
8. ลบงานทีละรายการ/ทั้งหมดระหว่าง polling ไม่มีงานคืนมาและ Backend ไม่ได้รับ cancel/delete
9. Dark Mode, Accessibility Dynamic Type ขนาดสูงสุด, VoiceOver, clipboard permission, Share sheet, safe-area และปุ่มเมื่อแป้นพิมพ์เปิด
10. health API=ok + worker=offline/needs_attention ต้องไม่แสดงว่า Bot พร้อม

## ตรวจ HTTP integration เมื่อมี Backend จริงหรือ test harness ภายนอก

- TLS ปกติ, 202 enqueue, 200 completed, 200 replay, 401/403, 404, 409, 429, 503 และ JSON error envelope
- POST timeout หลัง Backend รับแล้ว retry key เดิมได้ jobId เดิม; key เดิม + input ต่างต้อง 409
- Retry-After seconds/HTTP-date, body retryAfterSeconds และรอค่าที่มากกว่า โดยเฉพาะค่ามากกว่า 10 วินาที
- redirect ไปโดเมนอื่นต้องถูกปฏิเสธและไม่ส่ง Authorization ตามไป ตรวจ server logs ใน test harness โดยไม่ log secret
- malformed JSON, unknown status, วันที่ไม่ถูกต้อง, originalUrl/jobId ต่างจาก request, completed ไม่มี/ปลอม affiliateUrl ต้อง error ไม่ success
- GET ที่ใช้ token ของคนอื่นต้องอ่าน job ไม่ได้แม้รู้ ID
- verify ไม่มี ATS exception, custom trust bypass หรือ token logs

Backend Windows ผ่าน 18 tests รวม HTTP timeout หลัง SQLite รับงานแล้วและ retry key เดิม พร้อม live smoke test และการหยุด/เปิดใหม่ ดู backend/README.md ยังไม่ได้ทดสอบ HTTPS กับ iPhone หรือการสร้างลิงก์ผ่าน Shopee จริง
