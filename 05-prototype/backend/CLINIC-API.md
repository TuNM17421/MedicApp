# API phòng khám (web bác sĩ)

Hợp đồng giữa backend và `doctor_web`. Bước 14 có phần xem; bước 15 thêm kê đơn và gửi kết quả, bước 16 thêm phía người bệnh.

Mọi phản hồi là JSON UTF-8, `cache-control: no-store`. Lỗi có dạng `{ "error": { "code", "message" } }`, message tiếng Việt, không có stack trace. Ngày có dạng `yyyy-MM-dd`, thời điểm là ISO-8601 có múi giờ, luôn theo giờ phòng khám `+07:00` (ví dụ `2026-10-16T08:30:00+07:00`). Phía Dart cần `DateTime.parse(...).toLocal()` trước khi đưa vào `medic_core` (máy bác sĩ ở múi giờ Việt Nam), nếu không `dayOf` sẽ lấy ngày theo UTC.

Khi backend chạy mà không mở được cơ sở dữ liệu, mọi giao diện dưới đây trả `503 clinic_unavailable`.

## Đăng nhập

Phiên bác sĩ nằm trong cookie `mc_staff` (`HttpOnly; SameSite=Strict; Path=/`, thêm `Secure` khi chạy HTTPS). Phiên hết hạn sau 30 phút không thao tác (trượt) và tối đa 12 giờ. Phiên chỉ giữ trong bộ nhớ: khởi động lại server thì phải đăng nhập lại.

Web bác sĩ bản build được backend phục vụ ở `/doctor/` (cùng origin, nên cookie đi kèm mà không cần CORS). Khi chạy `flutter run -d web-server` ở cổng khác, đặt `DOCTOR_WEB_DEV_ORIGIN=http://localhost:<cổng>` để backend trả CORS có `credentials` cho đúng origin đó (không bao giờ `*`; preflight `OPTIONS` trả `204`). Cookie vẫn `SameSite=Strict`: `localhost:8080` và `localhost:<cổng khác>` là cùng site (cổng không làm khác site), nên trình duyệt vẫn gửi cookie khi web gọi `fetch` với `credentials: include`. Mở web bằng `localhost`, đừng trộn `localhost` với `127.0.0.1` (hai host khác site).

Bản build phục vụ ở `GET /doctor/*` từ `DOCTOR_WEB_DIR` (mặc định `../doctor_web/build/web`, cần `flutter build web --base-href /doctor/ --no-web-resources-cdn`). Đường dẫn không có tệp và không có phần mở rộng trả `index.html` (SPA); thiếu bản build: `404 doctor_web_missing`. `/` và `/doctor` chuyển về `/doctor/`.

| Giao diện | Thân | Trả về |
| --- | --- | --- |
| `POST /v1/staff/login` | `{ email, password }` | `200 { staff, clinic }` và đặt cookie. Sai: `401 bad_credentials`. Lần sai thứ 5 liên tiếp khóa 15 phút và trả `423 locked`; trong thời gian khóa, cả mật khẩu đúng cũng nhận `423`. |
| `POST /v1/staff/logout` | | `204`, xóa cookie |
| `GET /v1/staff/me` | | `200 { staff, clinic }`, hoặc `401 unauthenticated` |

`staff = { id, name: "BS. Nguyễn Thu Hà", role }`, `clinic = { id, name, phone }`.

Mọi giao diện dưới đây cần phiên hợp lệ (`401 unauthenticated`) và chỉ trả dữ liệu thuộc phòng khám của bác sĩ (khác phòng khám: `404 not_found`).

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
  "consent": { "state": "shared", "grantedAt", "expiresAt", "scope": ["intake", "dose_log", "self_meds"] },
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

`npm run seed` tạo `data/clinic.db` với phòng khám An Bình, bác sĩ `bs.ha@anbinh.test` (mật khẩu lấy từ `DEMO_PASSWORD`, mặc định `medicapp-demo`) và 6 người bệnh giống bản bấm thử, lịch khám vào ngày chạy seed (giờ Việt Nam, đổi bằng `SEED_TODAY=yyyy-MM-dd`). Lượt khám trước của Trần Văn Minh và Phạm Thị Lan là 30 ngày trước, lúc 06:30, để liều sáng của ngày đầu được tính; với quy tắc `medic_core`, Phạm Thị Lan ra Atorvastatin 18/30 và Allopurinol 27/30. Mã lượt khám có dạng `a-<người bệnh>-<yyyyMMdd>` (ví dụ `a-p2-20261016`). Chỉ dùng cho dev; seed xóa và tạo lại file, chỉ chấp nhận đường dẫn trong `backend/data` hoặc thư mục tạm.

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
