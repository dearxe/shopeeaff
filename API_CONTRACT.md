# Affiliate Link Helper: สัญญา Backend ฉบับเสนอ (v0.2)

มี Backend บน Windows ตาม endpoint หลักแล้ว ดู backend/README.md ระบบปัจจุบันเป็นคิวที่ผู้ดูแลสร้างลิงก์จริงผ่านเว็บไซต์ Affiliate; `openapi.yaml` เป็นสัญญาสำหรับแอปและการเปิด HTTPS ภายหลัง แอปไม่เรียก Shopee API และไม่ได้สร้าง Affiliate URL ด้วยการเติม query เอง

## การเชื่อมต่อ

Base URL เป็น HTTPS origin เช่น `https://backend.example.com` อนุญาต port เฉพาะที่ผู้ดูแลตั้งไว้ ไม่รองรับ path prefix, query, fragment หรือ credentials ใน URL ทุก request ส่ง `Accept: application/json` และ `Authorization: Bearer <private-connection-code>` POST เพิ่ม Content-Type และ Idempotency-Key

AuthProvider แยกจาก HTTPService เพื่อแทนที่ด้วย session/token รายผู้ใช้ได้ รหัสร่วมเหมาะกับการทดสอบส่วนตัวเท่านั้น ก่อนเปิดสาธารณะต้องมีการยืนยันตัวตน การเพิกถอน token และสิทธิ์รายผู้ใช้ ไม่ใส่ secret ใน repo/log รหัสเก็บใน Keychain แบบ ThisDeviceOnly

แอปใหม่ส่ง optional `tracking: { "channel": "tiktok", "subIdPrefixes": ["ios", "affiliate", "shop"] }` รองรับ channel `tiktok`, `facebook`, `line`, `instagram` ค่า tracking เป็นส่วนหนึ่งของข้อมูลที่ผูก idempotency key; เปลี่ยน channel หลัง timeout ไม่เปลี่ยน payload ของคำขอเดิม การ decode ประวัติเดิมที่ไม่มี tracking ยังทำได้

prefix เป็น intent ให้ Backend จัด Sub ID ตามรูปแบบและความยาวที่ integration ของบัญชีรองรับ ยังไม่อ้างว่าเป็นรูปแบบ Shopee ที่รับรองแล้ว Backend ต้องตรวจและ map ให้ถูกต้อง ไม่ให้แอปเติม query หรือรับ Affiliate ID ของเจ้าของจาก client บัญชีเจ้าของกำหนดที่ server configuration เท่านั้น ข้อมูลเจ้าของที่ได้รับคือ Affiliate ID `15349870042` เก็บอ้างอิงใน deployment/owner-config.example.json ไม่ฝังใน app source และไม่ใช่ credential สำหรับเรียก Shopee API

ทุก endpoint ต้องตรวจ principal งานและ idempotency mapping ต้องผูกกับ principal/device ที่มีสิทธิ์ การรู้ jobId ไม่พออ่านงานผู้อื่น GET ของงานที่ไม่ใช่เจ้าของคืน 404 เหมือนงานที่ไม่มีอยู่ HTTPService ปฏิเสธ redirect ทั้งหมด แม้ same-origin; Backend ต้องตอบจาก URL ที่ตั้งโดยตรง TLS/ATS ใช้ค่ามาตรฐาน

## สร้างงานและตรวจสถานะ

1. แอปสร้าง clientRequestId และ Idempotency-Key เป็น UUID คนละค่า เก็บ request ใน local file แบบ atomic ก่อน POST
2. `POST /v1/link-jobs` ส่ง `{ "clientRequestId": "UUID", "originalUrl": "https://shope.ee/example" }` รับ HTTP 202 พร้อม job ไม่เปิด request ค้างจน Bot จบ รองรับ 200 เมื่อมีผลแล้วหรือ replay งานเดิม
3. `GET /v1/link-jobs/{jobId}` รับสถานะปัจจุบัน Job ID จริงใช้ `[A-Za-z0-9_-]+` เท่านั้น
4. `GET /v1/health` รับ `{ "apiStatus": "ok", "workerStatus": "needs_attention" }` API ที่ตอบได้ไม่ได้รับประกัน Bot พร้อม

Job มี `jobId`, `status`, `originalUrl`, `createdAt`, `updatedAt` เสมอ วันเวลา ISO 8601 พร้อม timezone รองรับ fractional seconds optional `retryAfterSeconds` เป็นเลขไม่ติดลบ optional `error` ใช้โครงสร้างเดียวกับ error HTTP

|สถานะ|ความหมาย|ผลลัพธ์|
|---|---|---|
|queued|รอคิว|ไม่มี affiliateUrl|
|processing|กำลังสร้าง|ไม่มี affiliateUrl|
|waiting_for_operator|PC ต้องรอผู้ดูแล|ไม่มี affiliateUrl; ไม่ส่ง OTP/CAPTCHA ให้แอปจัดการ|
|completed|เสร็จแล้ว|ต้องมี affiliateUrl HTTPS ที่ผ่าน allowlist และไม่มี credentials|
|failed|Bot ล้มเหลวจริง|ต้องมี error; ไม่มี affiliateUrl|

jobId, createdAt และ originalUrl ต้องคงเดิม updatedAt ไม่ก่อน createdAt terminal state ไม่เปลี่ยนกลับ งาน completed ที่ไม่มี URL ถูกต้องถือเป็น response error แอปจะไม่แสดงสำเร็จและไม่เปิดลิงก์

Backend ต้อง resolve short URL และตรวจปลายทางเอง ป้องกัน redirect ไปปลายทางที่ไม่อนุญาตและ SSRF ก่อนให้ Bot เปิด URL แอปไม่ fetch หน้าเว็บสินค้าและไม่ตัด query ของลิงก์ต้นฉบับ

## Idempotency และข้อผิดพลาด

- key เดิม + request เดิมคืน jobId เดิมและสถานะล่าสุด ต้องบันทึก mapping กับการ enqueue เป็น atomic operation
- key เดิม + request ต่างคืน HTTP 409 / IDEMPOTENCY_CONFLICT และห้าม enqueue
- clientRequestId เดิมกับ input ต่างต้อง conflict เช่นกัน; ห้าม key ข้าม principal อ่านงานกันได้
- เก็บ idempotency mapping อย่างน้อยตลอดอายุที่งานยังอ่านได้ หากอนาคตกำหนด retention ต้องตกลงกับแอปก่อน ไม่ลบ mapping แล้วสร้างงานซ้ำจาก retry
- POST timeout ไม่รู้ว่า Backend รับหรือยัง แอปเก็บ pending request และให้ retry ด้วย key เดิมเท่านั้น กลับแอปจะไม่ POST pending อัตโนมัติ
- งาน failed และผู้ใช้กดสร้างใหม่เป็นคำขอใหม่ จึงใช้ UUID ใหม่ทั้งสองค่า
- HTTP error ใช้ `{ "error": { "code": "API_UNAVAILABLE", "message": "Temporarily unavailable", "retryable": true } }` ส่วน failed job มี object เดียวกันใน field `error`
- 401/403 ให้แก้สิทธิ์, 404 งานไม่มีหรือไม่มีสิทธิ์, 409 conflict, 429 รอตาม Retry-After, 503 ล่ม ข้อผิดพลาด transport/timeout ไม่เปลี่ยนสถานะ Bot เป็น failed

## Polling และ local scope

ขณะ foreground เริ่มรอประมาณ 2 วินาที เพิ่ม 2 → 3 → 4.5 → 6.75 → 10 วินาที Backend delay เป็นขั้นต่ำ ใช้ค่าที่มากกว่าระหว่าง body retryAfterSeconds และ header Retry-After (seconds หรือ HTTP-date) และค่าพื้นฐานของแอป `waiting_for_operator` รอขั้นต่ำ 30 วินาที

หยุดเมื่อ completed/failed; background ยกเลิก polling task; foreground ตรวจงานที่มี jobId ต่อ ไม่อ้างว่าทำงานต่อขณะ iOS ระงับแอป ปุ่ม manual check ก็เคารพเวลา Retry-After response/auth errors ที่ไม่ retryable พักจนผู้ใช้ตรวจใหม่

Mock history แยกตาม scenario Backend history แยกตาม normalized origin และ accountScope UUID ที่เปลี่ยนเมื่อบันทึก/ลบรหัส บันทึกรหัสเดิมซ้ำก็ถือเป็นบริบทใหม่เพื่อความปลอดภัย สลับกลับ origin เดิมด้วยบริบทเดิมจึงเห็นงานเดิม ข้อมูลเก่าจะไม่ถูกส่งไป origin ใหม่ การลบในเครื่องไม่ส่ง DELETE หรือ cancel Backend

## ตัวอย่างผลสำเร็จ (ใช้เอกสารเท่านั้น)

```json
{
  "jobId": "job_demo_001",
  "status": "completed",
  "originalUrl": "https://shope.ee/example",
  "affiliateUrl": "https://shopee.co.th/?contract_example=not_an_affiliate_link",
  "createdAt": "2026-09-30T03:00:00Z",
  "updatedAt": "2026-09-30T03:00:10Z"
}
```

URL ตัวอย่างทุกอันไม่ใช่ Affiliate จริง Mock ใช้ ID ภายในที่ encode request เพื่อจำลองการ relaunch และไม่ใช้รูปแบบ jobId ของ HTTP service เมื่อเชื่อม Backend จริงต้องคืนลิงก์ที่สร้างโดยระบบบัญชีเจ้าของเท่านั้น
