# API phòng khám (web bác sĩ)

Hợp đồng giữa backend, `doctor_web` và app người bệnh. Bước 14 có phần xem; bước 15 thêm kê đơn và gửi kết quả; bước 16 thêm phía người bệnh (đăng nhập bằng số điện thoại, đồng ý chia sẻ, gửi dữ liệu từ app); bước 18 thêm tài khoản do quản trị cấp, nhật ký truy cập, số liệu chạy thử, sao lưu và header bảo mật ([Quản trị và vận hành](#quản-trị-và-vận-hành-bước-18)).

Mọi phản hồi là JSON UTF-8, `cache-control: no-store`. Lỗi có dạng `{ "error": { "code", "message" } }`, message tiếng Việt, không có stack trace. Ngày có dạng `yyyy-MM-dd`, thời điểm là ISO-8601 có múi giờ, luôn theo giờ phòng khám `+07:00` (ví dụ `2026-10-16T08:30:00+07:00`). Phía Dart cần `DateTime.parse(...).toLocal()` trước khi đưa vào `medic_core` (máy bác sĩ ở múi giờ Việt Nam), nếu không `dayOf` sẽ lấy ngày theo UTC.

Khi backend chạy mà không mở được cơ sở dữ liệu, mọi giao diện dưới đây trả `503 clinic_unavailable`.

## Đăng nhập

Phiên bác sĩ nằm trong cookie `mc_staff` (`HttpOnly; SameSite=Strict; Path=/`, thêm `Secure` khi chạy HTTPS). Phiên hết hạn sau 30 phút không thao tác (trượt) và tối đa 12 giờ. Phiên chỉ giữ trong bộ nhớ: khởi động lại server thì phải đăng nhập lại.

Web bác sĩ bản build được backend phục vụ ở `/doctor/` (cùng origin, nên cookie đi kèm mà không cần CORS). Khi chạy `flutter run -d web-server` ở cổng khác, đặt `DOCTOR_WEB_DEV_ORIGIN=http://localhost:<cổng>` để backend trả CORS có `credentials` cho đúng origin đó (không bao giờ `*`; preflight `OPTIONS` trả `204`). Cookie vẫn `SameSite=Strict`: `localhost:8080` và `localhost:<cổng khác>` là cùng site (cổng không làm khác site), nên trình duyệt vẫn gửi cookie khi web gọi `fetch` với `credentials: include`. Mở web bằng `localhost`, đừng trộn `localhost` với `127.0.0.1` (hai host khác site).

Bản build phục vụ ở `GET /doctor/*` từ `DOCTOR_WEB_DIR` (mặc định `../doctor_web/build/web`, cần `flutter build web --base-href /doctor/ --no-web-resources-cdn`). Đường dẫn không có tệp và không có phần mở rộng trả `index.html` (SPA); thiếu bản build: `404 doctor_web_missing`. `/` và `/doctor` chuyển về `/doctor/`.

| Giao diện | Thân | Trả về |
| --- | --- | --- |
| `POST /v1/staff/login` | `{ email, password }` | `200 { staff, clinic }` và đặt cookie. Sai: `401 bad_credentials`. Lần sai thứ 5 liên tiếp khóa 15 phút và trả `423 locked`; trong thời gian khóa, cả mật khẩu đúng cũng nhận `423`. Tài khoản đã bị quản trị khóa: `403 account_disabled` (chỉ khi mật khẩu đúng). |
| `POST /v1/staff/logout` | | `204`, xóa cookie |
| `GET /v1/staff/me` | | `200 { staff, clinic }`, hoặc `401 unauthenticated` |
| `GET /v1/staff/session` | | Như `me`, nhưng chưa đăng nhập thì `200 null` (web dùng khi mở trang, để console không có lỗi 401) |
| `POST /v1/staff/password` | `{ currentPassword, newPassword }` | `200 { staff, clinic }`. Xem bước 18. |

`staff = { id, name: "BS. Nguyễn Thu Hà", role: "doctor" | "admin", mustChangePassword }`, `clinic = { id, name, phone }`.

Mọi giao diện dưới đây cần phiên hợp lệ (`401 unauthenticated`) và chỉ trả dữ liệu thuộc phòng khám của bác sĩ (khác phòng khám: `404 not_found`). Hàng chờ, hồ sơ, kết quả, lịch sử, danh mục và đánh giá tóm tắt chỉ dành cho vai trò `doctor`; tài khoản `admin` nhận `403 forbidden` (bước 18).

## Hàng chờ

`GET /v1/clinic/worklist?date=yyyy-MM-dd` (mặc định hôm nay theo giờ Việt Nam)

```json
{
  "date": "2026-10-16",
  "now": "2026-10-16T08:40:00+07:00",
  "items": [
    {
      "appointmentId": "a-...",
      "time": "08:30",
      "status": "arrived",
      "kind": "Khám dịch vụ",
      "specialty": "Nội tổng hợp",
      "patient": { "id": "p2", "code": "000482", "name": "Phạm Thị Lan", "age": 78, "gender": "Nữ" },
      "consent": "shared",
      "consentReason": null,
      "consentRevokedAt": null,
      "hasSummary": true,
      "chiefComplaint": "Đau khớp gối phải khoảng 1 tuần, sưng về đêm.",
      "flagged": false,
      "resultStatus": "none",
      "courses": [ ... ],
      "doseLog": [ ... ]
    }
  ]
}
```

- `status`: `booked` (chưa đến), `arrived`, `in_progress`, `done`, `cancelled`.
- `consent`: `shared` (đang chia sẻ), `declined` (đã từ chối hoặc đã rút lại), `none` (chưa trả lời).
- `consentReason`, `consentRevokedAt`: giống `consent.reason`, `consent.revokedAt` của hồ sơ bên dưới.
- `resultStatus`: `none`, `draft`, `sent`.
- `chiefComplaint`: nội dung mục `chief` của tóm tắt mới nhất khi `consent` là `shared` và có tóm tắt, nếu không thì `null` (cột "Lý do khám").
- `flagged`: tóm tắt có ít nhất một cờ.
- `courses`, `doseLog`: như ở hồ sơ bên dưới, chỉ có khi `consent` là `shared`, để web tự tính tỷ lệ tuân thủ bằng `medic_core` (backend không tính).

## Hồ sơ một lượt khám

`GET /v1/appointments/:id/chart`. Mỗi lần gọi ghi một `audit_event` (`chart.view`).

```json
{
  "appointment": { "id", "time": "08:30", "startsAt", "status", "kind", "specialty", "resultStatus" },
  "patient": {
    "id", "code", "name", "age", "gender", "birthDate",
    "address", "weightKg", "insuranceCode": "•••• 3921", "allergy",
    "conditions": ["Gút (M10)", "Rối loạn lipid máu (E78)"]
  },
  "consent": { "state": "shared", "grantedAt", "expiresAt", "scope": ["intake", "dose_log", "self_meds"], "reason": null, "revokedAt": null },
  "period": { "from": "2026-09-16", "days": 30, "now": "2026-10-16T08:40:00+07:00" },
  "summary": {
    "id", "mode": "mock", "createdAt",
    "sections": [ { "key": "chief", "text", "sources": ["i-1"] }, { "key": "course", ... }, { "key": "questions", ... } ],
    "flags": [ { "text", "sources": ["i-4"] } ],
    "feedback": null
  },
  "intake": [ { "id": "i-1", "channel": "booking", "question", "answer", "answeredAt" } ],
  "courses": [ { "id": "v-...#1", "visitId", "prescribedAt", "item": { PrescriptionItem } } ],
  "doseLog": [ { DoseLogEntry: "courseId", "day", "slot", "mark", "at", "reason" } ],
  "selfMeds": [ { "name", "how" } ],
  "lastVisit": { HistoryEntry hoặc null },
  "result": { ResultDraft hoặc null }
}
```

- `consent.state` là `shared`, `declined` hoặc `none`. Lấy bản ghi `consent` mới nhất của lượt khám: không có là `none`; đã rút (`revoked_at`), hết hạn hoặc phạm vi rỗng là `declined` (khi đó `grantedAt`, `expiresAt` là `null`, `scope` rỗng). Từng phần theo phạm vi: `intake` mở `summary` và `intake`, `dose_log` mở `courses` và `doseLog`, `self_meds` mở `selfMeds`. Khi không phải `shared`: `summary`, `intake`, `courses`, `doseLog`, `selfMeds` là `null`/`[]`. Cột người bệnh và lịch sử khám tại phòng khám vẫn trả về.
- `consent.reason` cho biết vì sao `declined`: `revoked` (người bệnh đã rút lại hoặc đã từ chối; `revokedAt` là lúc rút, ISO `+07:00`), `expired` (hết hạn chia sẻ; `revokedAt` là `null`), hoặc `null` (đang `shared`, chưa trả lời, hoặc phạm vi rỗng mà chưa rút). Web dùng để ghi "Người bệnh đã rút lại lúc …" hay "Đã hết hạn chia sẻ".
- `PrescriptionItem`, `DoseLogEntry` đúng dạng JSON của `medic_core` (`toJson`).
- `summary.feedback`: `null` hoặc `{ "value": "up" | "down", "by": "BS. Nguyễn Thu Hà", "at" }` (`by` là tên hiển thị).
- `patient.insuranceCode`: chỉ 4 số cuối (`"•••• 3921"`), `null` khi không dùng BHYT. `patient.weightKg` có thể `null`.
- `intake[].answer` là lời người bệnh, không kèm dấu ngoặc kép; `question` rỗng khi câu trả lời không gắn với câu hỏi cụ thể (ví dụ lúc đặt lịch). `channel`: `booking` hoặc `pre_visit`.
- `period`: 30 ngày ngay trước ngày khám (`from` = ngày khám − 30). `courses` là các đợt thuốc có ngày dùng nằm trong kỳ; `doseLog` là các liều đã ghi của những đợt đó trong kỳ. `courses[].visitId` là phần trước `#` của `id`.
- `lastVisit`: kết quả đã gửi gần nhất tại phòng khám trước lượt này. `result`: phiên bản kết quả mới nhất của chính lượt này (`ResultDraft`, xem bước 15), hoặc `null`.

`POST /v1/summaries/:id/feedback` thân `{ "value": "up" | "down" }`: `200 { feedback }`. Ghi `audit_event` (`summary.feedback`).

`POST /v1/appointments/:id/arrive` (từ `booked`) và `POST /v1/appointments/:id/start` (từ `booked` hoặc `arrived`): `200 { appointment }`. Sai trạng thái: `409 bad_state`. `start` gán bác sĩ đang đăng nhập nếu lượt khám chưa có bác sĩ. Cả hai ghi `audit_event` (`appointment.arrive`, `appointment.start`).

## Lịch sử khám

`GET /v1/patients/:id/history`: các kết quả đã gửi tại phòng khám, mới nhất trước. Mỗi lượt khám chỉ có bản `sent` hiện hành; bản `amended` và bản nháp không xuất hiện. Ghi `audit_event` (`history.view`).

```json
[ { "appointmentId", "date": "2026-09-16", "clinicName", "doctorName",
    "diagnosis": [["M10", "Gút"]], "items": [ PrescriptionItem ], "advice": "...",
    "followUpDate": "2026-10-16", "version": 1 } ]
```

## Dữ liệu mẫu

`npm run seed` tạo `data/clinic.db` với phòng khám An Bình, bác sĩ `bs.ha@anbinh.test` (mật khẩu lấy từ `DEMO_PASSWORD`, mặc định `medicapp-demo`) và 6 người bệnh giống bản bấm thử, lịch khám vào ngày chạy seed (giờ Việt Nam, đổi bằng `SEED_TODAY=yyyy-MM-dd`). Lượt khám trước của Trần Văn Minh và Phạm Thị Lan là 30 ngày trước, lúc 06:30, để liều sáng của ngày đầu được tính; với quy tắc `medic_core`, Phạm Thị Lan ra Atorvastatin 18/30 và Allopurinol 27/30. Mã lượt khám có dạng `a-<người bệnh>-<yyyyMMdd>` (ví dụ `a-p2-20261016`). Mỗi người bệnh có số điện thoại `0912` + mã người bệnh (xem bước 16). Chỉ dùng cho dev; seed xóa và tạo lại file, chỉ chấp nhận đường dẫn trong `backend/data` hoặc thư mục tạm.

## Kết quả khám và đơn thuốc (bước 15)

Một lượt khám có các phiên bản kết quả `version` 1, 2… Chỉ phiên bản mới nhất được sửa, và chỉ khi còn là `draft`. Bản đã gửi (`sent`) không bao giờ bị sửa: muốn sửa thì mở bản mới bằng `amend`, gửi bản mới thì bản cũ chuyển thành `amended`.

`ResultDraft`:

```json
{
  "id", "appointmentId", "version": 1, "status": "draft" | "sent" | "amended",
  "diagnosis": [["M10", "Gút"]],
  "items": [ PrescriptionItem ],
  "advice": "Uống đủ 2 lít nước mỗi ngày.",
  "followUpDate": "2026-11-13" | null,
  "internalNote": "",
  "amendReason": null | "Sửa liều Colchicin",
  "signedBy": null | "BS. Nguyễn Thu Hà", "signedAt": null | "...+07:00",
  "updatedAt": "...+07:00",
  "claimCode": null | "K7MQ-4XR2-9D"
}
```

| Giao diện | Việc |
| --- | --- |
| `GET /v1/clinic/catalog` | `{ drugs: [{ name, strength, form, route }], icd10: [["M10", "Gút"], …] }` cho ô tìm thuốc và chẩn đoán. Danh mục mẫu, chưa phải danh mục thuốc của phòng khám. |
| `GET /v1/appointments/:id/result` | Phiên bản mới nhất (`ResultDraft`) hoặc `null`. |
| `PUT /v1/appointments/:id/result-draft` | Thân `{ diagnosis, items, advice, followUpDate, internalNote }`. Tạo bản nháp nếu chưa có, hoặc ghi đè bản nháp mới nhất. Bản mới nhất đã gửi: `409 result_sent`. Kiểm tra kiểu dữ liệu và giới hạn độ dài, chưa bắt buộc đủ trường. |
| `POST /v1/appointments/:id/result/send` | Ký và gửi bản nháp mới nhất. Bắt buộc: ít nhất 1 chẩn đoán; mỗi thuốc có tên, số lượng nguyên dương, ít nhất 1 liều lớn hơn 0, số ngày 1–365. Thiếu: `422 incomplete` kèm `fields`. Lượt khám chuyển `done`; tạo `claimCode` nếu lượt khám chưa có. Ghi `audit_event` (`result.send`). |
| `POST /v1/appointments/:id/result/amend` | Thân `{ reason }` (bắt buộc). Bản mới nhất phải là `sent`; tạo bản nháp `version + 1` chép nội dung bản đó. Ghi `audit_event` (`result.amend`). |

Hồ sơ (`/chart`): `result` là `ResultDraft` mới nhất hoặc `null`; `appointment.resultStatus` theo bản mới nhất (`draft` khi đang sửa bản mới). Hàng chờ cũng vậy.

Chi tiết thêm:

- `PUT result-draft`, `send` trả `200 ResultDraft`; `amend` trả `201 ResultDraft` (bản nháp mới).
- `PUT result-draft`: sai kiểu hoặc quá dài trả `400 bad_draft` kèm `fields` (đường dẫn trường, ví dụ `items[0].quantity`, không kèm giá trị). Giới hạn: 10 chẩn đoán (mã ≤ 16, tên ≤ 200 ký tự), 20 thuốc, `name` ≤ 120, `strength` ≤ 40, `form`/`route` ≤ 20, `note` ≤ 300, `advice`/`internalNote` ≤ 2000. Trong bản nháp: `quantity`, `days` là số nguyên 0–10000 / 0–365, liều `amount` 0–100, mỗi buổi (`slot`) tối đa một liều; backend xếp liều theo thứ tự sáng, trưa, chiều, tối. Trường thiếu nhận giá trị rỗng (`form` mặc định `viên`, `route` `Uống`, `meal` `any`). Mã ICD được viết hoa. Lượt khám đã hủy: `409 bad_state`.
- `send` khi chưa có bản nháp: `409 no_draft`; bản mới nhất đã gửi: `409 result_sent`. `fields` của `422 incomplete` theo thứ tự: `diagnosis`, rồi `items[i].name`, `items[i].quantity`, `items[i].doses` (thiếu liều hoặc có liều bằng 0), `items[i].days`. Đơn không có thuốc vẫn gửi được.
- `amend`: thiếu lý do (hoặc dài hơn 500 ký tự) trả `422 incomplete` với `fields: ["reason"]`; bản mới nhất không phải `sent`: `409 not_sent`.
- `claimCode` là mã của lượt khám, có từ lần gửi đầu và hiện trên mọi phiên bản sau đó (kể cả bản nháp sửa).
- Lưu bản nháp ghi `audit_event` (`result.draft`).

## Người bệnh nhận kết quả bằng mã

Chưa có tài khoản người bệnh trên máy chủ (rủi ro R1 trong plan), nên bước 15 dùng **mã nhận kết quả**: in trên đơn giấy và hiện trên web sau khi gửi. Người bệnh nhập mã trong app để tải kết quả về lượt khám tương ứng.

- Mã gồm 10 ký tự Crockford base32 (khoảng 50 bit), hiển thị dạng `XXXX-XXXX-XX`, không phân biệt hoa thường, bỏ qua dấu gạch. Một mã cho một lượt khám, dùng cho mọi phiên bản; hết hạn 30 ngày sau lần gửi đầu.
- Khi nhập, `O` được hiểu là `0`, `I` và `L` là `1` (quy ước Crockford); khoảng trắng và dấu gạch bị bỏ qua.
- `GET /v1/results/claim/:code`, không cần đăng nhập. Mỗi IP tối đa 10 lần/phút (`429 rate_limited`). Sai hoặc hết hạn: `404 not_found`, cùng một thông báo. Ghi `audit_event` (`result.claim`, actor `patient`).
- Trả về bản đã gửi mới nhất theo dạng `VisitResult` của `medic_core`, trừ `visitId` và `profileId` (app tự gắn vào lượt khám của mình): `{ appointmentId, version, issuedAt, facilityName, facilityPhone, doctorName, patientName, patientAge, patientGender, address, insuranceCode (đã che, "" khi không dùng BHYT), weightKg (null khi không có), diagnosis: "Gút (M10); Rối loạn lipid máu (E78)", items, advice: ["…", "Hẹn tái khám ngày 13/11/2026."], followUpDate }`.
- `advice`: lời dặn tách theo dòng (bỏ dòng trống), thêm câu hẹn tái khám khi có `followUpDate`. `issuedAt` là lúc ký gửi bản đó; `patientAge` tính theo ngày khám.
- Dữ liệu mẫu: kết quả đã gửi của Trần Văn Minh có mã nhận. `npm run seed` in mã ra màn hình; đặt `SEED_CLAIM_CODE=K7MQ-4XR2-9D` để mã cố định khi demo.

## Người bệnh (bước 16)

Người bệnh đăng nhập bằng số điện thoại và mã xác nhận một lần (OTP), xem lịch khám và kết quả của mình, đồng ý chia sẻ theo từng lượt khám và gửi dữ liệu từ app lên phòng khám. Giải quyết rủi ro R1 trong plan (chưa có tài khoản người bệnh). Mã nhận kết quả của bước 15 vẫn dùng được.

### Số điện thoại

- `patient.phone` lưu dạng chuẩn `0xxxxxxxxx`, duy nhất trong một phòng khám, có thể trống. Một số có thể gắn với người bệnh ở nhiều phòng khám; phiên đăng nhập gắn với số điện thoại nên thấy lượt khám ở mọi phòng khám có số đó.
- Chuẩn hóa: bỏ khoảng trắng, dấu chấm, dấu gạch; `+84xxxxxxxxx` và `84xxxxxxxxx` thành `0xxxxxxxxx`. Hợp lệ khi là `0` và 9 chữ số. Sai: `422 bad_phone` (`fields: ["phone"]`).

### Đăng nhập

| Giao diện | Thân | Trả về |
| --- | --- | --- |
| `POST /v1/patient/otp` | `{ phone }` | `202 { expiresIn: 300, devCode }`. Cùng một câu trả lời dù số có trong hệ thống hay không (không dò được số); số lạ không được lưu mã nên không đăng nhập được. |
| `POST /v1/patient/session` | `{ phone, code }` | `200 { token, expiresAt, patient: { phone, name } }`. Sai mã, hết hạn, quá số lần hoặc số lạ: `401 bad_code` (một thông báo chung). |
| `DELETE /v1/patient/session` | | `204`, thu hồi token trong header (luôn `204`, kể cả khi token đã hết hạn hoặc không có). |

- Mã gồm 6 chữ số, hết hạn sau 5 phút, tối đa 5 lần nhập; lần sai thứ 5 xóa mã, phải xin mã mới. Mỗi số chỉ có một mã còn hiệu lực: xin mã mới thay mã cũ. Đăng nhập đúng thì mã bị xóa (chỉ dùng một lần).
- Mã lưu dạng HMAC-SHA256 với khóa bí mật của server (`PATIENT_OTP_PEPPER`; bản dev có giá trị mặc định, `NODE_ENV=production` bắt buộc đặt). Không lưu mã gốc.
- Giới hạn xin mã: 3 lần/10 phút mỗi số (kể cả số lạ), 10 lần/10 phút mỗi IP: `429 rate_limited`. Bộ đếm ở bộ nhớ, mất khi khởi động lại server.
- Chưa có nhà cung cấp SMS (việc của bước 18). `PATIENT_OTP_MODE`:
  - `dev` (mặc định khi `NODE_ENV` khác `production`): mã ghi vào log `{"event":"patient_otp","phone":"09•••••482","code":"123456"}` và trả trong `devCode` để app dev tự điền. Đặt `DEMO_OTP=000000` để mã luôn là `000000` (chỉ dùng khi demo với dữ liệu mẫu, chỉ có tác dụng ở chế độ `dev`).
  - `off` (mặc định khi `NODE_ENV=production`): `POST /v1/patient/otp` trả `503 otp_unavailable`.
- `patient.name` là tên ở lượt khám gần nhất của số điện thoại đó.
- Token: 32 byte ngẫu nhiên (base64url, 43 ký tự), chỉ lưu SHA-256 trong bảng `patient_session`, hết hạn sau 30 ngày (không trượt). Gửi trong header `Authorization: Bearer <token>`. Thiếu, sai, hết hạn hoặc đã đăng xuất: `401 unauthenticated`. Phiên lưu trong cơ sở dữ liệu nên khởi động lại server vẫn còn.

Mọi giao diện dưới đây cần token. Lượt khám không thuộc số điện thoại của phiên trả `404 not_found` như lượt không tồn tại.

### Lịch khám và kết quả

`GET /v1/patient/appointments`: mọi lượt khám của người bệnh có số này, ở mọi phòng khám, mới nhất trước.

```json
[
  {
    "id": "a-p2-20261016",
    "clinic": { "id": "c-anbinh", "name": "Phòng khám Đa khoa An Bình", "phone": "0900 000 000" },
    "startsAt": "2026-10-16T08:30:00+07:00", "time": "08:30",
    "specialty": "Nội tổng hợp", "kind": "Khám dịch vụ", "status": "arrived",
    "resultStatus": "none",
    "consent": { "state": "shared", "scope": ["intake", "dose_log", "self_meds"],
                 "grantedAt": "...", "expiresAt": "...", "revokedAt": null },
    "intakeCount": 4,
    "selfMeds": [ { "name": "Paracetamol 500mg", "how": "..." } ]
  }
]
```

- `resultStatus`: `sent` khi lượt khám có bản kết quả đã gửi, nếu không `none`. Bản nháp (kể cả bản sửa đang mở) không hiện cho người bệnh: khi đang sửa, người bệnh vẫn thấy `sent` và bản đã gửi trước đó.
- `consent` (`ConsentView`): bản ghi đồng ý mới nhất của lượt khám, hoặc `null` khi chưa có. `state`: `shared`, `revoked` (đã rút, hoặc đã từ chối), `expired` (quá `expiresAt`). `scope` là phạm vi của bản ghi đó.
- `intakeCount`: số câu trả lời trước khám đang lưu cho lượt khám; `selfMeds`: thuốc tự dùng đang lưu.

`GET /v1/patient/appointments/:id/result`: bản đã gửi mới nhất, cùng dạng với `GET /v1/results/claim/:code` (bước 15). Chưa có bản đã gửi: `404 not_found`. Ghi `audit_event` (`result.view`, actor `patient`).

Khi bác sĩ gửi kết quả (`POST /v1/appointments/:id/result/send`), mỗi thuốc trong đơn thành một dòng `med_course` của người bệnh: `id = "<appointmentId>#<n>"` (n từ 1 theo thứ tự trong đơn), `item` là `PrescriptionItem`, `prescribed_at` là lúc ký gửi lần đầu. Gửi bản sửa thay `item` của các dòng đó (giữ `prescribed_at`), thêm dòng mới nếu đơn dài hơn và xóa các dòng vượt quá nếu đơn ngắn hơn. App dùng các `id` này làm `courseId` khi gửi nhật ký liều.

### Đồng ý chia sẻ

Đồng ý theo từng lượt khám, tách khỏi đồng ý lưu dữ liệu trên máy. `ConsentView` như trên.

| Giao diện | Thân | Trả về |
| --- | --- | --- |
| `PUT /v1/patient/appointments/:id/consent` | `{ scope: ["intake", "dose_log", "self_meds"] (tập con, không rỗng, không trùng), wordingVersion: 1 }` | `200 ConsentView` (`shared`). Thêm một bản ghi mới; các bản còn hiệu lực trước đó bị rút (`revoked_at`). Ghi `audit_event` (`consent.grant`). |
| `DELETE /v1/patient/appointments/:id/consent` | | `200 ConsentView` (`revoked`). Ghi `audit_event` (`consent.revoke`) khi có bản bị rút. Gọi lại khi đã rút: `200`, không đổi gì. Chưa từng đồng ý: `404 not_found`. |

- `scope` được sắp theo thứ tự `intake`, `dose_log`, `self_meds`. Sai `scope` hoặc `wordingVersion` (số nguyên 1–1000): `422 bad_consent` kèm `fields`.
- `expiresAt` = giờ khám + 30 ngày; nếu thời điểm đó đã qua (lượt khám cũ) thì bây giờ + 30 ngày.
- Lượt khám đã hủy: `409 bad_state`.
- Rút lại thì lần tải tiếp theo của web bác sĩ không còn thấy tóm tắt, câu trả lời, thuốc và nhật ký liều, thuốc tự dùng (hồ sơ và hàng chờ, xem `consent.reason`). Lịch sử khám và kết quả do phòng khám tự ghi vẫn hiện. Hết hạn cũng vậy.
- Bước này **chưa xóa** dữ liệu đã gửi khi rút lại: các dòng vẫn nằm trong cơ sở dữ liệu nhưng bị ẩn. Bước 18 có test chứng minh dữ liệu đã rút không bao giờ trả về; xóa hẳn theo yêu cầu người bệnh vẫn chưa làm.

### Gửi dữ liệu từ app

Cần đồng ý đang hiệu lực (bản mới nhất của lượt khám, chưa rút, chưa hết hạn) có phạm vi tương ứng, nếu không `403 consent_required`. Sai dạng dữ liệu: `400 bad_upload` kèm `fields` (ví dụ `answers[0].answer`, không kèm giá trị); dữ liệu được kiểm tra trước khi kiểm tra đồng ý. Thân tối đa 512 KiB (các giao diện khác 16 KiB). Mỗi token tối đa 60 lần gửi/phút (`429 rate_limited`). Thời điểm gửi lên là ISO-8601 có múi giờ (`Z` hoặc `+07:00`), server lưu theo giờ `+07:00`.

| Giao diện | Thân | Trả về |
| --- | --- | --- |
| `PUT /v1/patient/appointments/:id/intake` | `{ answers: [{ id, channel: "booking" \| "pre_visit", question, answer, answeredAt }] }`, tối đa 50 | `200 { count }`: số câu trả lời đang lưu cho lượt khám. Phạm vi `intake`. |
| `PUT /v1/patient/appointments/:id/self-meds` | `{ items: [{ name, how }] }`, tối đa 30 | `200 { count }`. Thay toàn bộ danh sách cũ. Phạm vi `self_meds`. |
| `POST /v1/patient/dose-events` | `{ events: [{ courseId, day: "yyyy-MM-dd", slot, mark, reason, at }] }`, tối đa 500 | `200 { accepted, ignored: [courseId…] }`. Phạm vi `dose_log`. |

- `intake`: `id` do app tạo (uuid, 1–64 ký tự), `question` ≤ 300 ký tự (có thể rỗng hoặc bỏ), `answer` 1–2000 ký tự. Ghi đè theo `id`; server lưu `id` dạng `<appointmentId>/<id>` nên một `id` không chạm được lượt khám khác. Gửi lại cùng `id` là sửa câu trả lời, không thêm dòng. Hồ sơ bác sĩ trả `intake[].id` theo dạng đã lưu.
- `self-meds`: `name` 1–120 ký tự, `how` ≤ 200 (có thể bỏ). Danh sách rỗng xóa hết.
- `dose-events`: `slot` là `morning`, `noon`, `afternoon`, `evening`; `mark` là `taken` hoặc `skipped`; `reason` là `null` hoặc `forgot`, `outOfStock`, `unwell`, `other` (chỉ lưu khi `skipped`); `at` là lúc ghi. Ghi đè theo (người bệnh, `courseId`, `day`, `slot`), nên gửi lại cùng một liều không tạo dòng mới.
  - Một liều được nhận khi `courseId` là một dòng `med_course` của người bệnh có số điện thoại này **và** người bệnh đó có ít nhất một lượt khám với đồng ý đang hiệu lực có `dose_log`. Các liều khác bị bỏ qua, `courseId` của chúng có trong `ignored` (mỗi mã một lần).
  - Không người bệnh nào của số này có đồng ý `dose_log` đang hiệu lực: `403 consent_required`.
- Gửi câu trả lời và thuốc tự dùng ghi `audit_event` (`intake.upload`, `self_meds.upload`, actor `patient`).
- Gửi câu trả lời xong, server hẹn tạo tóm tắt trước khám ở nền (bước 17, xem [Tóm tắt trước khám](#tóm-tắt-trước-khám-bước-17)); phản hồi không chờ tóm tắt.

### Dữ liệu mẫu

`npm run seed` gán số `0912` + mã người bệnh và in ra (`patientPhones`):

| Người bệnh | Số điện thoại | Đồng ý chia sẻ lượt hôm nay |
| --- | --- | --- |
| Trần Văn Minh (000317) | `0912000317` | có, đủ 3 phạm vi; có kết quả đã gửi |
| Phạm Thị Lan (000482) | `0912000482` | có, đủ 3 phạm vi |
| Phạm Văn Hòa (000455) | `0912000455` | đã từ chối (`revoked`) |
| Lê Thị Mai (000501) | `0912000501` | có, đủ 3 phạm vi |
| Đỗ Văn Tùng (000233) | `0912000233` | chưa trả lời |
| Vũ Thị Hạnh (000519) | `0912000519` | có, đủ 3 phạm vi |

Demo: đặt `DEMO_OTP=000000` trong `.env`, chạy server, trong app nhập `0912000482` rồi mã `000000`. Không đặt `DEMO_OTP` thì lấy mã ở `devCode` hoặc trong log server.


## Tóm tắt trước khám (bước 17)

Tóm tắt trong `summary` của hồ sơ (`GET /v1/appointments/:id/chart`) và cột "Lý do khám", `flagged` của hàng chờ. **Dạng trả về không đổi** so với bước 14: `{ id, mode, createdAt, sections: [{ key, text, sources }], flags: [{ text, sources }], feedback }`; mỗi cờ có thêm `signs` (nhãn dấu hiệu, ví dụ `["đau ngực"]`), web cũ bỏ qua được.

### Khi nào chạy

- Sau `PUT /v1/patient/appointments/:id/intake` thành công (và khi người bệnh đồng ý lại có phạm vi `intake` mà lượt khám đã có câu trả lời), server hẹn một lần tóm tắt ở nền rồi trả lời ngay; việc tóm tắt **không bao giờ làm chậm** lần gửi.
- Gộp theo lượt khám: chờ `SUMMARY_DEBOUNCE_MS` (mặc định 3 giây) không có câu mới mới chạy, nên gửi liền nhiều lần chỉ chạy một lần. Câu mới đến khi đang chạy thì chạy thêm đúng một lần sau đó, trên toàn bộ câu trả lời. Hàng đợi nằm trong tiến trình (tối đa 2 lần chạy song song); khởi động lại server thì lần hẹn chưa chạy bị bỏ, lần gửi sau hẹn lại.
- Chỉ chạy khi bản đồng ý mới nhất của lượt khám còn hiệu lực và có `intake`; kiểm tra lại sau khi model trả về, rút đồng ý giữa chừng thì bỏ kết quả. Lượt khám đã hủy hoặc chưa có câu trả lời: không chạy.
- Không ghi đè: mỗi lần chạy thêm một dòng `visit_summary` (`mode`, `model`, `prompt_version` = `summary-v1`, `input_hash`); hồ sơ trả dòng mới nhất (`created_at`, rồi thứ tự ghi). Câu trả lời không đổi so với lần trước (cùng `mode`, `prompt_version`) thì không tạo dòng mới. Đánh giá 👍/👎 gắn với từng bản. Không còn mục nào và không có cờ thì không ghi dòng (bản cũ vẫn hiện).
- Mỗi lần chạy ghi `audit_event` `summary.generate`, actor `system`, `detail` gồm `result` (`created`, `empty`, `failed`), `summaryId`, `mode`, `model`, `promptVersion`, số câu trả lời, các mục, số cờ, các phần bị bỏ và lý do; không có lời người bệnh. Log chỉ có số đếm, chế độ, mã lỗi và độ trễ.

### Chế độ

`CLINIC_AI_SUMMARY` (mỗi server phục vụ một phòng khám nên đây là cấu hình theo phòng khám):

| Giá trị | Hành vi |
| --- | --- |
| `auto` (mặc định) | Như `mock`, kể cả khi có `OPENAI_API_KEY`: câu trả lời chỉ gửi OpenAI khi đặt rõ `openai` |
| `off` | Không tạo tóm tắt. Hồ sơ vẫn trả bản cũ nếu có |
| `mock` | Quy tắc cố định, không gọi model: mỗi câu trả lời vào một mục theo câu hỏi (câu "muốn hỏi bác sĩ" → `questions`; thuốc tự dùng, diễn biến → `course`; lúc đặt lịch → `chief`), lấy tối đa 2 câu đầu của mỗi mục, cắt gọn ở cuối câu. `mode` là `mock`, web hiện "Mô phỏng AI" |
| `openai` | Responses API như Smart Scheduling: `OPENAI_MODEL`, `OPENAI_REASONING_EFFORT`, Structured Outputs (`strict: true`), `store: false`, `MAX_OUTPUT_TOKENS`, timeout `MODEL_TIMEOUT_MS`, lỗi mạng/timeout thử lại một lần, không đổi sang model khác. Cần key, thiếu key thì server không khởi động |

`/health` có `summary_mode`.

### Dữ liệu gửi model và các mục

- Đầu vào **chỉ** là các dòng `intake_answer` của lượt khám: `channel`, `question`, `answer`, với id rút gọn `a1`, `a2`… (không lộ mã lượt khám). Không gửi tên, số điện thoại, mã BHYT, địa chỉ, tuổi, bệnh nền hay thuốc đã kê; nếu người bệnh tự viết tên, số điện thoại, mã BHYT hoặc địa chỉ của mình trong câu trả lời thì server thay bằng `[tên]`, `[số điện thoại]`, `[mã BHYT]`, `[địa chỉ]` trước khi gửi.
- Model trả `{ sections: [{ key, sentences: [{ text, sources: [id] }] }] }`, `key` là `chief` (lý do khám), `course` (diễn biến, thuốc người bệnh tự dùng như họ kể) hoặc `questions` (điều muốn hỏi). Thuốc tự dùng nằm trong `course` (thẻ "Diễn biến, đã tự xử lý" của web), không có mục riêng.
- Prompt cấm chẩn đoán, khuyên thuốc, tự gắn cờ và **mọi con số người bệnh không nói** (tỷ lệ tuân thủ, số liều quên, phần trăm): các số đó do code tính (web tính tuân thủ bằng `medic_core` từ `courses`, `doseLog`).

### Kiểm tra phía server (`src/summary/guard.js`)

1. Bỏ câu không có `sources` hoặc trích id không phải câu trả lời của lượt khám này; bỏ `key` lạ; tối đa 4 câu mỗi mục, mỗi câu ≤ 300 ký tự.
2. Bỏ **cả mục** khi một câu có con số (chữ số, hoặc số viết bằng chữ có dấu như "hai", "mười") hoặc tên thuốc không có trong chính các câu trả lời nó trích. Số viết bằng chữ trong câu trả lời ("hai hôm") khớp với chữ số trong tóm tắt ("2 ngày"). Tên thuốc theo danh sách mẫu `src/summary/drug-names.json` (hoạt chất và biệt dược cùng nhóm coi là một: "panadol" ↔ "paracetamol") cộng tên trong `catalog/clinic-catalog.json`; danh sách chưa được dược sĩ duyệt.
3. Mục còn lại ghép thành `{ key, text, sources }` (nguồn là hợp các câu), thứ tự `chief`, `course`, `questions`.

Bộ kiểm tra chạy cả ở chế độ `mock`.

### Cờ cần chú ý

- Do **code** tìm theo danh sách cụm từ `src/summary/red-flags.json`, không do model: đau ngực, khó thở, ngất, yếu liệt nửa người, nói khó, nôn ra máu, ho ra máu, đi ngoài phân đen, co giật, có ý định tự tử, đau đầu dữ dội, lú lẫn. Danh sách ghi rõ **"cần bác sĩ phòng khám đối tác duyệt trước khi dùng"** (`reviewed: false`).
- So khớp không phân biệt dấu ("dau nguc" khớp "đau ngực"), theo từ trọn vẹn, có danh sách loại trừ cho cụm trùng chữ khác nghĩa ("ngạt mũi" gõ không dấu là "ngat mui", không phải "ngất").
- Phủ định đơn giản: cụm bị bỏ qua khi trước nó, trong cùng mệnh đề (ngắt bởi dấu câu) và trong 6 từ, có "không", "chưa", "chẳng", "chả", "ko", "k"…, và giữa hai bên không có từ mở ý mới ("nhưng", "mà", "vì", "khi", "lúc", "thỉnh thoảng"…). Ví dụ: "không đau ngực hay khó thở" không gắn cờ; "không sốt nhưng khó thở", "không biết có phải đau ngực không" vẫn gắn cờ. Khi không chắc thì gắn cờ.
- Mỗi câu trả lời có dấu hiệu cho một cờ: `text` là (các) câu nguyên văn chứa dấu hiệu, `sources` là id câu trả lời đó, `signs` là nhãn. Cờ không đánh giá mức độ.

### Đánh giá

`npm run eval:summary` chạy 30 hội thoại mẫu tiếng Việt (`eval/summary-cases.json`: bệnh mạn tái khám, bệnh cấp, người cao tuổi, tự dùng thuốc, gõ không dấu, có dấu hiệu nguy hiểm, có câu phủ định, chỉ có câu hỏi) qua đúng pipeline của server, in bảng và thoát mã 1 nếu có ca không đạt. Tiêu chí: 100% câu được giữ có nguồn hợp lệ; không câu nào có số hay tên thuốc ngoài câu được trích; bắt đủ mọi cờ mong đợi, không cờ nào trên câu phủ định hay thừa. Chế độ `openai` khi đặt `CLINIC_AI_SUMMARY=openai` (có key), nếu không `mock`; `npm run eval:summary -- --mock` ép `mock`.

**Chưa kiểm chứng:** chưa chạy với OpenAI bằng key thật (chất lượng câu chữ, tỷ lệ bị bộ kiểm tra bỏ, độ trễ, chi phí). Danh sách dấu hiệu và tên thuốc là bản mẫu.


## Quản trị và vận hành (bước 18)

### Vai trò và tài khoản

- `practitioner.role` là `doctor` hoặc `admin`. Quản trị (`admin`) cấp và khóa tài khoản, xem số liệu chạy thử và nhật ký truy cập; **không** xem hàng chờ, hồ sơ, kết quả (`403 forbidden`). Bác sĩ gọi giao diện quản trị cũng nhận `403 forbidden`. Một người vừa là bác sĩ vừa quản trị thì có hai tài khoản.
- Seed tạo quản trị `quantri@anbinh.test`, cùng mật khẩu `DEMO_PASSWORD` (mặc định `medicapp-demo`).
- Mật khẩu: tối thiểu 10 ký tự, tối đa 256, không trùng email (bỏ qua hoa thường, khoảng trắng), mật khẩu mới khác mật khẩu hiện tại. Lưu bằng scrypt (N=16384, r=8, p=1, muối 16 byte). Sai 5 lần liên tiếp khóa 15 phút. Phiên 30 phút không thao tác, tối đa 12 giờ (giữ như bước 14).
- **Mật khẩu tạm**: 12 ký tự chữ thường và số dễ đọc, dạng `k7mq-4xr2-9dpt` (khoảng 59 bit), chỉ trả **một lần** trong phản hồi tạo hoặc đặt lại, không ghi log. Tài khoản có mật khẩu tạm có `mustChangePassword: true`; trước khi đổi, mọi giao diện trừ `me`, `session`, `logout`, `password` trả `403 password_change_required`. Web chỉ hiện màn đổi mật khẩu.
- Khóa tài khoản (`deactivate`) kết thúc mọi phiên của người đó ngay; yêu cầu tiếp theo nhận `401`. Đặt lại mật khẩu cũng kết thúc phiên và gỡ khóa do nhập sai.

| Giao diện | Ai | Thân | Trả về |
| --- | --- | --- | --- |
| `POST /v1/staff/password` | người đã đăng nhập (kể cả đang có mật khẩu tạm) | `{ currentPassword, newPassword }` | `200 { staff, clinic }`. Mật khẩu yếu: `422 weak_password` (`fields: ["newPassword"]`, message nói lý do). Sai mật khẩu hiện tại: `400 wrong_password`, tính vào số lần sai; lần thứ 5 khóa 15 phút, kết thúc mọi phiên, trả `423 locked`. Đổi xong, các phiên khác của tài khoản kết thúc, phiên này giữ nguyên. Audit `staff.password_change`. |
| `GET /v1/clinic/staff` | admin | | `200 [StaffAccount]`. Audit `staff.list`. |
| `POST /v1/clinic/staff` | admin | `{ email, fullName, role: "doctor" \| "admin", title?, licenseNo? }` | `201 { staff: StaffAccount, temporaryPassword }`. `title` mặc định `BS.` cho bác sĩ, rỗng cho quản trị. Sai: `422 bad_staff` kèm `fields`; email đã có (ở bất kỳ phòng khám nào): `409 email_taken`. Audit `staff.create`. |
| `POST /v1/clinic/staff/:id/deactivate` | admin | | `200 { staff }`. Tự khóa mình: `409 self`. Audit `staff.deactivate` (kèm số phiên đã kết thúc). |
| `POST /v1/clinic/staff/:id/reactivate` | admin | | `200 { staff }`. Audit `staff.reactivate`. |
| `POST /v1/clinic/staff/:id/reset-password` | admin | | `200 { staff, temporaryPassword }`. Với chính mình: `409 self` (dùng `POST /v1/staff/password`). Audit `staff.reset_password`. |

`StaffAccount = { id, name, role, mustChangePassword, fullName, title, email, licenseNo, active, locked (đang bị khóa do nhập sai), createdAt, lastLoginAt | null }`. Tài khoản của phòng khám khác: `404 not_found`.

### Nhật ký truy cập

Đọc từ `audit_event` của người bệnh: ai, làm gì, lúc nào, lượt khám nào.

- `GET /v1/patients/:id/access-log?limit=50&offset=0` (bác sĩ hoặc quản trị của phòng khám).
- `GET /v1/clinic/access-log?patientCode=000482&limit=&offset=` (cùng dạng; quản trị không có hàng chờ nên tra theo mã người bệnh).

```json
{
  "patient": { "id": "p2", "code": "000482", "name": "Phạm Thị Lan" },
  "total": 12, "offset": 0, "nextOffset": 2,
  "items": [
    { "id": 41, "at": "2026-10-16T08:41:00+07:00",
      "actor": { "kind": "staff", "name": "BS. Nguyễn Thu Hà", "role": "doctor" },
      "action": "chart.view", "label": "Mở hồ sơ lượt khám",
      "appointmentId": "a-p2-20261016", "visitDate": "2026-10-16" }
  ]
}
```

- Mới nhất trước. `limit` 1–100 (mặc định 50), `offset` ≥ 0; sai: `400 bad_page`. `nextOffset` là `null` ở trang cuối.
- `actor.kind`: `staff` (tên hiển thị và vai trò), `patient` ("Người bệnh"), `system` ("Hệ thống", ví dụ tạo tóm tắt).
- `label` là câu tiếng Việt theo `action` (`ACTION_LABELS` trong `src/clinic/admin.js`), ví dụ `consent.revoke` → "Rút lại đồng ý chia sẻ", `result.claim` → "Nhận kết quả bằng mã".
- Không trả `detail` hay IP của bản ghi audit (không lộ nội dung, phạm vi, số câu trả lời).
- Mỗi lần xem nhật ký ghi `audit_event` `access_log.view`, nên người xem cũng hiện trong nhật ký.

### Số liệu chạy thử

`GET /v1/clinic/pilot-metrics?from=yyyy-MM-dd&to=yyyy-MM-dd` (admin). Mặc định 30 ngày đến hôm nay; tối đa 366 ngày; sai: `400 bad_range`. Audit `pilot_metrics.view`.

```json
{ "from": "2026-09-17", "to": "2026-10-16",
  "totals": { "visits": 8, "withSummary": 4, "summaries": 4, "feedbackUp": 1, "feedbackDown": 1, "upRate": 0.5,
              "sent": 3, "received": 1, "medianMinutes": 180, "p90Minutes": 180, "amended": 1 },
  "days": [ { "date": "2026-10-16", "...": "cùng các trường" } ] }
```

Cách tính (theo plan: số lượt có tóm tắt, tỷ lệ bác sĩ bấm Đúng, thời gian từ lúc khám xong đến lúc người bệnh nhận kết quả, số đơn phải sửa sau khi gửi):

- **Lượt khám**: lịch hẹn của phòng khám có giờ khám trong khoảng ngày, trừ lượt đã hủy. `days` chỉ có ngày có lượt khám, theo ngày khám.
- **Có tóm tắt** (`withSummary`): lượt có ít nhất một dòng `visit_summary`. `summaries` là số bản tóm tắt.
- **Tỷ lệ Đúng** (`upRate`): `feedbackUp / (feedbackUp + feedbackDown)` trên các bản tóm tắt đã được đánh giá; `null` khi chưa có đánh giá. Mỗi bản tính đánh giá cuối cùng.
- **Khám xong** = lần ký gửi kết quả đầu tiên của lượt khám (`min(visit_result.signed_at)`). Ở hệ thống này gửi kết quả cũng chuyển lượt khám sang `done`, và không có nút "kết thúc khám" riêng, nên đây là mốc duy nhất đáng tin. **Người bệnh nhận** = `audit_event` đầu tiên `result.claim` (nhập mã) hoặc `result.view` (xem trong app) của lượt khám từ mốc đó. `sent` là số lượt đã gửi, `received` số lượt đã nhận; `medianMinutes`, `p90Minutes` (phút, percentile theo hạng gần nhất) chỉ tính trên lượt đã nhận, `null` khi chưa có.
- **Đơn phải sửa** (`amended`): lượt có bản kết quả đã gửi rồi bị thay bằng bản sửa đã gửi (có dòng `status = 'amended'`). Bản sửa đang nháp chưa tính.

### Bảo mật HTTP

- Mọi phản hồi có `x-content-type-options: nosniff`, `x-frame-options: DENY`, `referrer-policy: no-referrer`, `cross-origin-opener-policy: same-origin`, `cross-origin-resource-policy: same-origin`, `permissions-policy` tắt camera, micro, vị trí. API (JSON) có `cache-control: no-store` và `content-security-policy: default-src 'none'; frame-ancestors 'none'`.
- Web bác sĩ (`/doctor/*`): `cache-control: no-cache` và CSP chỉ cho phép cùng origin: `script-src 'self' 'wasm-unsafe-eval' 'sha256-…'` (CanvasKit biên dịch WebAssembly; không có `unsafe-eval` cho JavaScript; hash là đúng một script inline gói `printing` thêm để in đơn, test tính lại hash), `style-src 'self' 'unsafe-inline'` (Flutter đặt style inline), `connect-src 'self'`, `img-src 'self' data: blob:`, `frame-src 'self' blob:` (xem trước bản in PDF), `object-src 'none'`, `frame-ancestors 'none'`. Không tải gì từ CDN: CanvasKit gói trong bản build, dấu ✓ lấy từ font kèm theo; ký tự lạ (chữ Hán, emoji) hiện ô trống thay vì tải font Noto từ Google.
- `HTTPS=1` (server đứng sau reverse proxy có TLS): thêm `strict-transport-security: max-age=31536000; includeSubDomains` và cookie `Secure`.
- Thân yêu cầu tối đa 16 KiB (gửi dữ liệu từ app 512 KiB, `413 too_large`), WebSocket 256 KiB mỗi khung; header phải xong trong 20 giây, cả yêu cầu trong 60 giây.

### Tách phòng khám và đồng ý (plan §8)

`test/isolation.test.js` dựng phòng khám thứ hai có bác sĩ, quản trị, người bệnh đã chia sẻ đủ và kết quả đã gửi, rồi chứng minh: bác sĩ phòng khám A nhận `404` với mọi tài nguyên của B (hồ sơ, kết quả, nháp, gửi, sửa, đến khám, bắt đầu, lịch sử, nhật ký theo id và theo mã, đánh giá tóm tắt) và ngược lại, hàng chờ không có lượt của B; quản trị A không thấy, không khóa, không đặt lại tài khoản B, số liệu chỉ đếm lượt của mình; token người bệnh chỉ thấy lượt khám của số điện thoại mình (5 giao diện của lượt người khác đều `404`, nhật ký liều cho thuốc của người khác bị bỏ qua); sau khi rút đồng ý hoặc hết hạn, hồ sơ, hàng chờ, nhật ký truy cập không còn câu trả lời, tóm tắt, thuốc tự dùng, nhật ký liều, và đánh giá tóm tắt trả `404`. Không tìm thấy chỗ rò rỉ nào cần sửa.

### Sao lưu và phục hồi

Xem [README](README.md#sao-lưu-và-phục-hồi-bước-18).

