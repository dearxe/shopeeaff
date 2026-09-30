# Affiliate Link Helper: เตรียมเผยแพร่จริง

สถานะ ณ 30 กันยายน 2026: source ต้นแบบพร้อม แต่ยังไม่มีผล build/test บน Mac, Backend จริง, signing, App Store Connect app record หรือ build ที่อัปโหลด ไม่ถือว่าแอปพร้อมใช้งานจริงหรือพร้อมเผยแพร่แล้ว

## ข้อมูลที่เจ้าของต้องเตรียม

1. เจ้าของไม่มี Mac; เตรียม GitHub-hosted macOS workflow แล้วตาม NO_MAC_DEPLOYMENT.md ยังต้องรันจริงและทดสอบบน iPhone
2. เจ้าของแจ้งว่ามี Apple Developer Program และ GitHub แล้ว repository คือ `dearxe/shopeeaff` ยังต้องตรวจสิทธิ์และรับ Team ID จริง คำว่า `dearxe` ไม่ใช่ Team ID เจ้าของเป็นผู้เข้าสู่ระบบ/ยืนยันตัวตนเอง ไม่ส่ง Apple password, OTP หรือ private signing keys ในแชต
3. ชื่อผู้เผยแพร่ บุคคล/องค์กร อีเมล support ประเทศที่จะเผยแพร่ และ Bundle ID ที่เป็นของบัญชีเจ้าของ
4. บัญชีเจ้าของ Affiliate ID `15349870042` ปัจจุบันสร้างลิงก์ผ่านเว็บ Affiliate เท่านั้น ยังไม่ได้ยืนยันสิทธิ์ Open API ต้องเลือก integration ที่บัญชี/ผู้ให้บริการอนุญาตก่อนสร้าง worker ไม่ต้องใส่ ID/secret ในแอป
5. เจ้าของมี PC Windows ที่เปิดต่อเนื่องได้ แต่ Backend/Tailscale ยังไม่ได้ติดตั้ง ต้องสร้างและทดสอบ Backend HTTPS ตาม API_CONTRACT.md ในขั้นใหม่ก่อนเปิดใช้งานจริง
6. ชื่อ/อีเมลเจ้าของสำหรับนโยบายความเป็นส่วนตัว URL นโยบายและ support ที่เปิดได้จริง รายละเอียดข้อมูลที่ Backend เก็บและระยะเวลาเก็บ

## งานก่อนส่ง Apple

- ทดสอบ code ที่มีอยู่บน Mac แก้ compiler/test failures และทดสอบ iPhone จริงตาม TESTING.md
- สำหรับแอปสาธารณะ: กำหนด production Backend ใน release configuration และแทนรหัสร่วมส่วนตัวด้วยสิทธิ์ต่อผู้ใช้/อุปกรณ์ ไม่ให้ผู้ใช้ทั่วไปต้องตั้ง Backend ของเจ้าของเอง ไม่ใช้ผลจำลองแทนผลจริง
- เชื่อมระบบสร้าง Affiliate จริงและทดสอบปลายทาง การ retry/idempotency และการแยกสิทธิ์ผู้ใช้
- app icon สร้างและใส่ใน asset catalog แล้ว ยังต้องมี screenshots จากแอปที่รันจริง, คำอธิบายภาษาไทย, support/privacy links ในแอปและ metadata
- ทบทวน App Privacy และ PrivacyInfo.xcprivacy ตามข้อมูลที่แอปและ Backend เก็บจริง ห้ามใช้ข้อความต้นแบบเป็นคำรับรอง production
- ตั้ง signing/Bundle ID/version/build ภายใต้บัญชีเจ้าของ สร้าง archive และตรวจ validation
- อัปโหลด TestFlight และทดสอบ flow จริง เตรียมข้อมูลที่ App Review ใช้เข้าถึงระบบได้ หากต้อง login ให้มีบัญชีตรวจสอบที่เหมาะสม
- ส่ง review และตั้ง release ผ่าน App Store Connect ในบัญชีเจ้าของ การอนุมัติและเวลาอนุมัติเป็นการตัดสินใจของ Apple

## ข้อกำหนดที่ตรวจจาก Apple

ตั้งแต่ 28 เมษายน 2026 การอัปโหลด iOS app ต้อง build ด้วย iOS 26 SDK หรือใหม่กว่า ค่า deployment target ของ LinkAff ยังคงเป็น iOS 17 ได้; SDK ที่ใช้ build กับ OS ขั้นต่ำที่รองรับเป็นคนละค่า ดู [SDK requirements](https://developer.apple.com/news/?id=ueeok6yw)

แอปทุกตัวต้องมี Privacy Policy URL และระบุข้อมูล privacy ใน App Store Connect ดู [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

ต้องทดสอบบนอุปกรณ์จริง เตรียมข้อมูล review และเปิด Backend ให้ผู้ตรวจเข้าถึงได้ ดู [App Review](https://developer.apple.com/app-store/review/) และ [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

เอกสารนี้ไม่ได้สร้างบัญชี ไม่ได้ชำระค่าสมาชิก ไม่ได้เชื่อมบัญชี Shopee และไม่ได้เผยแพร่แอปหรือ server
