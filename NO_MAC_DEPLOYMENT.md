# Affiliate Link Helper: build และเผยแพร่จาก Windows

เจ้าของมี GitHub และ PC Windows ที่เปิดต่อเนื่องได้แล้ว หน้าบัญชี Apple ที่เจ้าของส่งมายังแสดง Join/Enroll the Apple Developer Program จึงยังไม่มีสมาชิกที่พร้อมใช้เผยแพร่และยังไม่มี Team ID ที่ยืนยัน ไม่ต้องซื้อ Mac เพื่อรัน pipeline นี้ ใช้ GitHub-hosted macOS runner; ต้องมี repository access และ signing material ก่อนเริ่ม [GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## สิ่งที่ตั้งแล้ว

|รายการ|ค่า|
|---|---|
|ชื่อบน iPhone / ชื่อที่จะใช้ใน Store|Affiliate Link Helper|
|Bundle ID|com.simplelifesolution.affiliatehelper|
|App Group ที่เสนอ|group.com.simplelifesolution.affiliatehelper|
|บัญชี Affiliate เจ้าของ (ข้อมูล server)|15349870042|
|ช่องทาง|TikTok, Facebook, LINE, Instagram|
|prefix hints|ios, affiliate, shop|
|ธีม|ขาว/ivory และส้ม copper พร้อม Dark Mode accent|
|การเผยแพร่ที่ต้องการ|Public App Store|

ชื่อ folder, scheme และ Swift module ยังคง LinkAff เพื่อรักษา tests/โครงสร้างเดิม ชื่อที่ผู้ใช้เห็นและ Bundle ID เปลี่ยนแล้ว App Group template อยู่ deployment/AppGroup.entitlements แต่ยังไม่เปิด entitlement ใน app เพราะเวอร์ชันนี้ยังไม่มี extension หรือ shared container ที่ต้องใช้ หากเพิ่ม Share Extension ให้ register group ใน Apple Developer และผูก provisioning profile/entitlements ของทั้งสอง targets พร้อมกัน

Affiliate ID ไม่ถูกส่งเป็น credential และไม่ถูกนำมาต่อท้าย URL การมี ID อย่างเดียวไม่ทำให้สร้างลิงก์ที่ผูกบัญชีได้จริง ต้องยืนยันวิธีที่บัญชีรองรับ (Open API หรือการสร้างผ่านหน้า Affiliate) ก่อนทำ Backend/worker ในขั้นถัดไป

## ขั้นแรก: รัน build/tests โดยยังไม่ต้อง signing

1. ส่ง repository URL เพื่อผูกงานกับ repo จริง หรือสร้าง private repository แล้วอัปโหลด source ทุก folder **รวม .github** โดยไม่อัปโหลด .git, ZIP หรือ signing files
2. ไป Actions → **iOS Build and Tests** → Run workflow
3. Runner `macos-26` ใช้ Xcode/iOS SDK ของเครื่องและตรวจว่า SDK >=26 จากนั้นเลือก iPhone Simulator ที่มีจริงและรัน XCTest
4. ดาวน์โหลด `ios-test-results` เพื่ออ่าน Xcode version, build-test.log และ Tests.xcresult ถ้าไม่ผ่านต้องแก้และรันใหม่

workflow นี้ยังไม่เคยรันใน session นี้ การมีไฟล์ workflow ไม่ใช่ผล build ผ่าน Private repositories ใช้ allowance/ค่าใช้จ่ายตาม GitHub plan ตรวจ usage ก่อนรันต่อเนื่อง [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

repository URL คือ `https://github.com/dearxe/shopeeaff.git` เชื่อม GitHub ผ่าน browser login ด้วยบัญชี dearxe และ push branch `codex/affiliate-helper-ios` สำเร็จแล้ว วิธี device code ของ bundled credential manager เกิด incorrect_device_code จึงเปลี่ยนสคริปต์ Login-GitHub.ps1 ให้ใช้ browser login เป็นค่าเริ่มต้น ไม่ขอให้ส่ง token ในแชต ผล build/test ยังต้องตรวจ GitHub Actions ต่อ

## Signing โดยไม่ใช้ Mac ส่วนตัว

สมัคร Apple Developer Program ให้เสร็จก่อน ผ่าน [Apple enrollment](https://developer.apple.com/programs/enroll/) เจ้าของเป็นผู้ยืนยันตัวตน/ยอมรับข้อตกลง/ชำระค่าสมาชิกเอง เมื่อสมาชิก active เปิด Membership details แล้วรับ Team ID 10 ตัว ตาม [Team ID help](https://developer.apple.com/help/glossary/team-id/) ขณะนี้ยังไม่สร้าง signing material เพราะไม่มีสมาชิก active/Team ID ที่ยืนยัน

หากมี distribution certificate และ private key อยู่แล้ว ให้ใช้คู่เดิมที่ได้รับอนุญาต ไม่ต้องสร้างใหม่ หากไม่มี สามารถสร้าง CSR ด้วยสคริปต์ PowerShell 7.2+ บน Windows:

```powershell
.\scripts\New-AppleSigningCSR.ps1 -Email 'อีเมลบัญชีของคุณ'
```

สคริปต์ยังไม่ได้รันสร้าง key จริงในงานนี้ ไฟล์ private key จะอยู่ `.signing/distribution-private.pem` ที่ถูก gitignore ไว้ เก็บในเครื่องส่วนตัวและ backup ที่ปลอดภัย ไม่ส่งในแชต ส่วน CSR `.certSigningRequest` ใช้อัปโหลดใน Apple Developer เพื่อออก **Apple Distribution certificate** แล้วดาวน์โหลด `.cer` การใช้ CSR/ออก certificate ขึ้นกับสิทธิ์ของบัญชี ดู [Apple certificate help](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)

ใน Apple Developer ต้องมี explicit App ID `com.simplelifesolution.affiliatehelper` และ App Store Connect provisioning profile ที่ใช้ distribution certificate คู่นี้ จากนั้นดาวน์โหลด `.mobileprovision` สร้าง app record ใน App Store Connect ด้วย Bundle ID เดียวกัน

สร้าง GitHub Environment ชื่อ `app-store` แล้วตั้ง:

|ชนิด|ชื่อ|ข้อมูล|
|---|---|---|
|Variable|APPLE_TEAM_ID|Team ID ของบัญชีเจ้าของ|
|Secret|SIGNING_CERTIFICATE_BASE64|base64 ของไฟล์ Apple `.cer` แบบ DER|
|Secret|SIGNING_PRIVATE_KEY_BASE64|base64 ของ PEM private key ที่สร้าง CSR คู่นั้น|
|Secret|PROVISION_PROFILE_BASE64|base64 ของ App Store provisioning profile|
|Secret|ASC_KEY_ID|App Store Connect Team API Key ID สำหรับอัปโหลด|
|Secret|ASC_ISSUER_ID|Issuer ID ของ Team API Key|
|Secret|ASC_PRIVATE_KEY_BASE64|base64 ของ AuthKey `.p8` ที่ดาวน์โหลดจาก Apple|

สามค่า ASC จำเป็นเมื่อเลือก upload เท่านั้น ตั้งผ่าน GitHub Secrets โดยตรง ไม่พิมพ์ค่าในแชตหรือ log ใช้ Team API key ที่มีสิทธิ์อัปโหลด ดู [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

แปลงไฟล์เป็น base64 และคัดลอกไป clipboard ในเครื่องได้โดยไม่ print secret:

```powershell
# แทน path ด้วยไฟล์ที่ต้องการ ตั้งทีละ secret ใน GitHub
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\to\file')) | Set-Clipboard
```

Actions → **Signed iOS Archive and Optional TestFlight Upload** → Run workflow จะรัน tests ก่อน จากนั้นสร้าง temporary keychain ตรวจ Bundle ID/team/expiry ของ profile, archive และ export IPA หากเลือก upload จะ validate และอัปโหลด App Store Connect เพื่อ TestFlight การอัปโหลดนี้ไม่ใช่การ submit App Review หรือเปิดขายสาธารณะ ดู [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)

ยังต้องทดสอบบน iPhone จริงผ่าน TestFlight ให้ได้ก่อนเปิด Public App Store Certificate/profile/API key, pipeline และไฟล์ IPA ยังไม่ได้สร้างหรือทดสอบจริงใน session นี้

## Tailscale URL

กำหนด **ชื่อเครื่องที่เสนอ** เป็น `affiliatehelper-api` URL จะเป็น `https://affiliatehelper-api.<ชื่อ-tailnet-จริง>.ts.net` เมื่อเครื่องถูกตั้งชื่อและเชื่อมบัญชีจริง ชื่ออาจถูกเติม suffix หากซ้ำ นี่คือ template ไม่ใช่ endpoint ที่เปิดแล้ว ไม่ใส่ template เป็นค่าเริ่มต้นในแอป

ผู้ใช้ทั่วไปไม่อยู่ใน tailnet ส่วนตัว จึงต้องใช้ **Funnel/public HTTPS endpoint** สำหรับ API ไม่ใช้ private Serve URL ที่ reviewer เข้าไม่ได้ Funnel จำกัดชื่อไว้ใน tailnet domain และมี bandwidth limits ต้องประเมินให้ตรงโหลดจริง ดู [Funnel](https://tailscale.com/docs/features/tailscale-funnel)

เมื่อมี Backend จริงที่ bind เฉพาะ loopback เช่น 127.0.0.1:8080 และตั้ง public authentication/rate limits แล้ว ผู้ดูแลจึงค่อยเปิด Funnel ด้วยคำสั่งตาม [Funnel CLI](https://tailscale.com/docs/reference/tailscale-cli/funnel) และคัดลอก URL จาก output ตอนนี้ยังไม่เปิด Funnel ไม่ติดตั้ง Tailscale ไม่ expose service มี Windows Backend แบบผู้ดูแลที่ bind loopback แล้ว ดู backend/README.md ยังไม่มี Bot สร้างลิงก์อัตโนมัติ

## สิ่งที่ยังขาดก่อน Public App Store

- repo URL, Apple Team ID และ access ที่จำเป็นเพื่อรัน pipeline/อัปโหลดจริง
- Backend และ worker ที่สร้าง Affiliate ของบัญชีเจ้าของได้จริง พร้อม ownership/idempotency/rate limits
- production onboarding และ session/token ต่อผู้ใช้หรืออุปกรณ์ แทน prototype shared code/หน้าตั้งค่า Backend ของลูกค้า
- public Backend URL, support email/URL, privacy policy URL และ disclosures ตรงระบบจริง
- ผล build/tests, iPhone testing, screenshots จากแอปจริง และข้อมูลให้ผู้ตรวจเข้าถึงบริการ

เมื่อครบจึงเตรียม metadata ส่ง App Review และเผยแพร่ภายใต้บัญชีเจ้าของ ไม่รับประกันการอนุมัติของ Apple
