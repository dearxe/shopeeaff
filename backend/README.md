# Backend บน Windows

API: `http://127.0.0.1:8080` — หน้าผู้ดูแล: [เปิดหน้าผู้ดูแล](http://127.0.0.1:8081)

ระบบบันทึกคิวใน SQLite และทำงานแบบผู้ดูแลสร้างลิงก์จริงผ่านเว็บไซต์ Shopee Affiliate ของตนเอง ยังไม่มี Bot สร้างลิงก์อัตโนมัติ ไม่สร้าง Affiliate URL ด้วยการเติม ID ลงใน URL

## เริ่มใช้งาน

เปิด PowerShell ในโฟลเดอร์โปรเจกต์ แล้วคัดลอกรหัสผู้ดูแลไปยัง clipboard:

```powershell
.\scripts\Copy-BackendCode.ps1 -Purpose operator
```

เปิดหน้าผู้ดูแล วางรหัสเพื่อเข้าสู่ระบบ ส่งลิงก์สินค้าจริงและเลือกช่องทาง จากนั้นสร้างลิงก์ผ่านบัญชี Shopee Affiliate ของคุณ กรอก URL สินค้าเต็มและ Affiliate URL ที่ได้จริง ตรวจสินค้าและบัญชีเจ้าของก่อนยืนยันผล ระบบพยายามตรวจปลายทางลิงก์; หาก Shopee ปิดกั้นการตรวจ ต้องอาศัยการยืนยันโดยผู้ดูแล ซึ่งไม่ใช่หลักฐานการรับค่าคอมมิชชันจาก Shopee

## เปิดและหยุด

```powershell
.\scripts\Install-Backend.ps1 # ติดตั้งครั้งแรก
.\scripts\Start-Backend.ps1
.\scripts\Stop-Backend.ps1
```

เปิดเฉพาะ loopback บนเครื่องนี้ ไม่เปิด LAN/อินเทอร์เน็ต และยังไม่ได้ตั้ง Windows Service หรือเริ่มอัตโนมัติเมื่อเปิดเครื่อง เครื่องต้องไม่พักการทำงาน หลังรีสตาร์ตให้รัน Start อีกครั้ง งานที่บันทึกไว้ยังอยู่

## API และรหัสอุปกรณ์

รองรับ `POST /v1/link-jobs`, `GET /v1/link-jobs/{jobId}`, `GET /v1/health` ตาม [สัญญา API](../API_CONTRACT.md) ทุกคำขอต้องมี Bearer token; POST ต้องมี Idempotency-Key งานและ key แยกตามเจ้าของ token งานของผู้อื่นตอบ 404 และ key เดิมกับข้อมูลต่างตอบ 409

ใช้ `Copy-BackendCode.ps1 -Purpose client` สำหรับรหัสอุปกรณ์เริ่มต้น รหัสนี้แยกจากรหัสผู้ดูแล อย่าส่งรหัสลงแชตหรือ GitHub สร้าง/เพิกถอนอุปกรณ์ได้ด้วย:

```powershell
.venv\Scripts\python.exe -m backend.manage provision-client --help
.venv\Scripts\python.exe -m backend.manage list-clients
.venv\Scripts\python.exe -m backend.manage revoke-client --help
```

Health รายงาน worker เป็น `needs_attention` ในโหมดผู้ดูแล แม้ API ทำงานปกติ Prefix และช่องทางเป็นข้อมูลให้ผู้ดูแลใช้ตามรูปแบบที่บัญชี Shopee รองรับ

iPhone ต้องใช้ HTTPS ที่เข้าถึง PC ได้ ขั้นถัดไปคือจัด HTTPS/Tailscale และตั้งค่าการเข้าถึง API โดยไม่เผยแพร่พอร์ตผู้ดูแล 8081 ยังไม่ได้ติดตั้ง Tailscale และไม่มี URL สาธารณะ แอปไม่มีการลดข้อกำหนด TLS เพื่อใช้ localhost HTTP

## ข้อมูลและการตรวจสอบ

ข้อมูลส่วนตัวอยู่ `.local/backend/` รวมฐานข้อมูล `jobs.sqlite3`, รหัสเชื่อมต่อ และบันทึกกระบวนการ โฟลเดอร์นี้และ `.venv` ถูกละเว้นจาก Git จำกัดสิทธิ์ไฟล์ให้บัญชี Windows ปัจจุบันและ SYSTEM สำรองข้อมูลโดยหยุด Backend ก่อนแล้วคัดลอกทั้งโฟลเดอร์ส่วนตัวไปยังพื้นที่ส่วนตัวที่ปลอดภัย

```powershell
.venv\Scripts\python.exe -m unittest discover -s backend/tests -v
.venv\Scripts\python.exe scripts/Smoke-Backend.py
```

ทดสอบบน Windows ผ่าน 18 รายการ รวม HTTP timeout หลังบันทึกงานจริง, retry โดยไม่เกิดงานซ้ำ, SQLite หลังเปิดใหม่, สิทธิ์ข้ามอุปกรณ์, CSRF และการตรวจ URL/redirect มี workflow `backend-tests.yml` สำหรับทดสอบบน Windows CI ด้วย ยังไม่ได้ยืนยันการสร้างลิงก์จริงผ่านบัญชี Shopee, การคิดค่าคอมมิชชัน, การเชื่อมต่อ iPhone หรือรองรับผู้ใช้สาธารณะ
