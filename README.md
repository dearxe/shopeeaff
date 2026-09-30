# Affiliate Link Helper — แอป iPhone สร้างลิงก์ผ่าน Backend

Native SwiftUI สำหรับ iOS 17 ขึ้นไป ภาษาไทย 3 แท็บ สร้างลิงก์ / ประวัติ / ตั้งค่า รองรับ Dark Mode และใช้ system fonts สำหรับ Dynamic Type ไม่มี external dependency ไม่ต้องมี server เพื่อทดลอง Mock Mode

เจ้าของไม่มี Mac ส่วนตัว: เริ่มจาก `NO_MAC_DEPLOYMENT.md` เพื่อใช้ GitHub Actions บน macOS สำหรับ build/test และเตรียม signing/IPA/TestFlight repository คือ https://github.com/dearxe/shopeeaff.git CI build/test รอบแรกผ่านแล้ว

ชื่อแอปคือ Affiliate Link Helper, Bundle ID `com.simplelifesolution.affiliatehelper` มีไอคอนขาว–ส้มแบบ Lux และช่องทาง TikTok/Facebook/LINE/Instagram แล้ว ชื่อโฟลเดอร์/module/scheme ยังคง LinkAff การเลือกช่องทางส่ง tracking intent ไป Backend; แชร์ผ่าน iOS Share Sheet ตามที่แต่ละแอปรองรับ ไม่ได้โพสต์อัตโนมัติหรือรับประกันว่า TikTok/Instagram รองรับการแชร์ URL โดยตรง

**สถานะส่งมอบ:** มี source, Xcode project, Mock/HTTP Service, XCTest และ proposed API contract ครบ Build และ XCTest ผ่านบน iPhone Simulator ของ GitHub-hosted Mac แล้วเมื่อ 30 กันยายน 2026: https://github.com/dearxe/shopeeaff/actions/runs/36672202935 ยังไม่ได้ทดสอบ iPhone จริง, signing, TestFlight หรือ Backend จริง อ่านรายละเอียดใน `TESTING.md`

## เปิดบน Mac และ Simulator

1. ย้ายโฟลเดอร์ทั้งหมดไป Mac ที่มี Xcode พร้อม iOS SDK/Simulator (source ใช้ Swift 5.9 ขึ้นไป; project ใช้ Swift 5 language mode)
2. เปิด `LinkAff.xcodeproj` เลือก scheme **LinkAff** และ iPhone Simulator ที่เป็น iOS 17 หรือใหม่กว่า
3. กด Run (⌘R) เริ่มใน Mock Mode / สำเร็จตามปกติ ไม่ต้อง signing สำหรับ Simulator
4. วาง `https://shopee.co.th/product/example?ref=test` หรือข้อความแชร์ที่มี URL เดียว ปุ่มวางอ่าน clipboard เมื่อกดเท่านั้น
5. กดสร้าง จะเห็นรอคิว → กำลังสร้าง → สำเร็จ ผลจำลองใช้ URL ที่ระบุว่าไม่ใช่ Affiliate ปุ่มเปิดสินค้าถูกปิด ปุ่มแชร์แนบป้ายจำลองไปด้วย

เปลี่ยนสถานการณ์ในตั้งค่าแล้วกดบันทึก เพื่อทดลองครบ 8 แบบ ข้อมูลจำลองแยกตาม scenario โหมด timeout จำลอง Backend รับ POST แล้วแอปไม่ได้ response: กดส่งคำขอเดิมอีกครั้งจากรายละเอียดงานเพื่อใช้ key เดิม โหมด rate limit ตอบ 429 ครั้งแรกแล้วลองอีกครั้งได้หลัง 5 วินาที โหมดรอผู้ดูแล polling ต่ำสุด 30 วินาที จึงอาจข้ามช่วง processing ที่สั้นใน mock และแสดง completed ในครั้งถัดไป

```sh
xcodebuild -list -project LinkAff.xcodeproj
xcodebuild -project LinkAff.xcodeproj -scheme LinkAff \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -showdestinations -project LinkAff.xcodeproj -scheme LinkAff
# แทน SIMULATOR_UDID ด้วย id จากคำสั่งข้างบน
xcodebuild -project LinkAff.xcodeproj -scheme LinkAff \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  CODE_SIGNING_ALLOWED=NO test
```

## iPhone จริงและ signing

1. เพิ่ม Apple Account ใน Xcode Settings → Accounts
2. เลือก target LinkAff → Signing & Capabilities → Automatically manage signing แล้วเลือก Team
3. Bundle Identifier ตั้งเป็น `com.simplelifesolution.affiliatehelper` แล้ว ต้องลงทะเบียน explicit App ID เดียวกันในทีม Apple Developer ของเจ้าของ test target ใช้ `com.simplelifesolution.affiliatehelper.tests`
4. เชื่อม iPhone ที่ใช้ iOS 17+ ให้ Mac เชื่อถืออุปกรณ์ เปิด Developer Mode ตามคำแนะนำของ iPhone/Xcode และเลือกอุปกรณ์เป็น destination
5. Run และทำตามคำแนะนำเรื่อง provisioning/trust ที่ Xcode แสดง Personal Team มีข้อจำกัดของการติดตั้งทดสอบ ไม่ใช่ช่องทาง TestFlight

## ตั้ง Backend ภายหลัง

สร้าง Backend บน PC แล้ว ดู [คู่มือ Backend](backend/README.md) และเปิดหน้าผู้ดูแลที่ http://127.0.0.1:8081 ระบบใช้ผู้ดูแลสร้างลิงก์จริงผ่านเว็บไซต์ Shopee Affiliate ยังต้องจัด HTTPS สำหรับ iPhone; `https://backend.example.com` ยังเป็น placeholder

- ใส่ HTTPS origin เท่านั้น ไม่มี path `/v1` และไม่ใช้ localhost เพื่ออ้างถึง PC จาก iPhone
- ใส่รหัสเชื่อมต่อส่วนตัวผ่าน SecureField แล้วบันทึก รหัสเก็บ Keychain ไม่เก็บใน local JSON
- ปิด Mock Mode และกดบันทึก กดทดสอบการเชื่อมต่อที่บันทึกไว้ ดู API และ Bot แยกกัน
- เชื่อมต่อไม่ได้จะเป็นข้อผิดพลาดจริง ไม่มี fallback ไปผลจำลอง
- เปลี่ยน URL หรือบันทึกรหัสใหม่ทำให้เห็นประวัติของบริบทใหม่ งานเก่าไม่ถูกส่งไปเซิร์ฟเวอร์ใหม่ รหัสใหม่แม้ข้อความเหมือนเดิมถือเป็นบัญชีใหม่ ไม่ผสมประวัติ
- ปรับ allowlist hostname ในตั้งค่าได้ แต่ต้องอนุญาตเฉพาะโดเมนที่ไว้ใจ แอปไม่ resolve short link เอง

ไม่ต้องใส่ Shopee password, cookies, Affiliate ID/Secret ของลูกค้า ระบบจริงต้องสร้าง Affiliate URL ผูกบัญชีเจ้าของที่ Backend ผู้ดูแลจัดการ OTP/CAPTCHA บน PC เอง

## โครงสร้างและสมมติฐาน

|ไฟล์|หน้าที่|
|---|---|
|LinkAffApp.swift / Views.swift|UI, scene lifecycle และ user actions|
|AppModel.swift|ViewModel, submit, resume, polling และ dependency injection|
|Models.swift|สถานะ Backend, request, response และ local record|
|URLValidator.swift|HTTPS/hostname allowlist และตรวจ response|
|Networking.swift|URLSession async/await, retry hints, ไม่ตาม redirect|
|MockService.swift|สถานการณ์จำลองในเครื่อง|
|Storage.swift|atomic JSON ใน Application Support และ Keychain/AuthProvider|
|LinkAffTests|URL, idempotency, resume, environment และ polling tests|

เลือก JSON storage แบบ atomic แทน SwiftData สำหรับข้อมูลขนาดเล็ก ไม่มี database server มี file protection; ไม่มีการเข้ารหัสไฟล์เพิ่ม ข้อมูลลิงก์/ประวัติอาจอยู่ใน device backup ตามระบบ iOS; secret เป็น ThisDeviceOnly ไม่ควรแชร์ device backup หรือไฟล์ประวัติที่มีลิงก์ส่วนตัว

ประวัติแยกตาม environment รหัสคำขอจะบันทึกก่อน POST ไม่ส่งซ้ำอัตโนมัติเมื่อไม่ทราบผล ปิดปุ่มขณะ submit และไม่ยอมสร้างคำขอใหม่ขณะมี pending request ที่ยังไม่ทราบผล เพื่อให้ตรวจคำขอเดิมก่อน งาน failed สร้างใหม่ด้วย key ใหม่ได้

ตรวจทุกงานค้างของ environment ขณะ foreground หยุด background/terminal; polling 2–10 วินาที ตาม backoff และเคารพ retry hints ที่ยาวกว่า รอผู้ดูแลขั้นต่ำ 30 วินาที ไม่ทำ push/background task ไม่แสดงรายได้ ราคา หรือรูปสินค้าที่ไม่มีข้อมูลจริง

เมื่อ local file เสีย จะขึ้น error และไม่ส่งงานใหม่เพื่อไม่สูญเสีย idempotency แบบเงียบ ๆ ต้องตรวจ/กู้ข้อมูลก่อนหรือ reset app โดยยอมรับผลของการสูญเสีย local records การลบประวัติไม่ยกเลิกงาน Backend และการลบ pending request จะสูญเสียช่องทาง retry key เดิมจาก UI

## เตรียม TestFlight

สำหรับการเผยแพร่จริง อ่าน `RELEASE_PLAN.md` เพิ่มเติม ณ 30 กันยายน 2026 Apple กำหนดให้ build สำหรับอัปโหลดด้วย iOS 26 SDK หรือใหม่กว่า โดย deployment target ของแอปยังตั้ง iOS 17 ได้ ดู [ข้อกำหนด SDK ของ Apple](https://developer.apple.com/news/?id=ueeok6yw)

ต้องมี Mac/Xcode รุ่นที่ Apple รับให้อัปโหลดในขณะนั้น, สมาชิก Apple Developer Program, สิทธิ์ใน App Store Connect, Bundle ID/app record และ distribution signing ที่ตรงกัน ดูข้อกำหนดปัจจุบันที่ [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds) และ [แนวทาง distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)

1. build/test และตรวจบน iPhone จริงตาม `TESTING.md` ก่อน archive
2. AppIcon asset 1024×1024 แบบ opaque RGB ใส่ในโปรเจกต์แล้ว ตรวจการแสดงไอคอนบนอุปกรณ์ พร้อมตั้ง version/build number, beta description, contact และข้อมูลทดสอบ
3. ตรวจ privacy manifest และ App Privacy ให้ตรง Backend/ข้อมูลที่เก็บจริง ไฟล์ปัจจุบันประกาศ UserDefaults สำหรับข้อมูลในเครื่องเท่านั้น ต้องทบทวน disclosures เมื่อมี Backend จริง อย่าฝังรหัสร่วมเพื่อแจกแอปสาธารณะ
4. เลือก Any iOS Device → Product → Archive → Organizer → Distribute App → App Store Connect แล้วอัปโหลด รอ processing และตอบเรื่อง export compliance ตามการใช้ encryption จริง
5. ตั้งผู้ทดสอบภายในใน TestFlight; การทดสอบภายนอกต้องเตรียมข้อมูลสำหรับ Beta App Review ตาม [TestFlight ของ Apple](https://developer.apple.com/testflight/)

ยังไม่มี archive/IPA, signing team, App Store Connect record หรือการอัปโหลด TestFlight ในงานนี้ การติดตั้งบน Windows โดยตรงและการเปิด Xcode Simulator บน Windows ทำไม่ได้

## ตรวจโครงสร้างบน Windows

```powershell
.\scripts\Verify-Structure.ps1
```

ตรวจ PBX references/source paths และ XML ไม่ใช่การ compile Swift หากเพิ่ม source ให้ปรับ `scripts/New-XcodeProject.ps1` แล้วรันเพื่อสร้าง project ใหม่ **สคริปต์สร้าง project จะเขียนทับ project.pbxproj** จึงเก็บการเปลี่ยน signing/build settings ที่ทำใน Xcode ก่อนใช้ หรือแก้ project ใน Xcode โดยตรง
