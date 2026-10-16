# Backend Smart Scheduling — chạy local

**PRD hiện hành:** [Smart Scheduling](../prd-smart-scheduling-implementation.md). Mô tả phía app: [SMART-SCHEDULING.md](../flutter_app/SMART-SCHEDULING.md).

Server Node.js 22 chạy trên máy tính, chỉ bind `127.0.0.1`. App trên điện thoại gọi qua USB (`adb reverse`). API key chỉ nằm trong `backend/.env`, không vào APK, log hoặc phản hồi.

## Cài và chạy

```powershell
# Chạy từ C:\Coding\MedicApp\05-prototype\backend (cần Node.js 22 trở lên)
npm ci
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
npm start
```

Kiểm tra: mở `http://127.0.0.1:8080/health`. Kết quả cho biết `mode`, model và các giới hạn, không trả key.

| Chế độ | Khi nào | Hành vi |
| --- | --- | --- |
| `mock` | `OPENAI_API_KEY` trống (mặc định `SMART_MODE=auto`) hoặc `SMART_MODE=mock` | Trích xuất bằng quy tắc mẫu tiếng Việt. App hiện nhãn **Mô phỏng AI**. Không nhận giọng nói; micro báo chưa hỗ trợ thay vì giả vờ nghe. |
| `openai` | Có key, hoặc `SMART_MODE=openai` | Hỏi đáp: Responses API `OPENAI_MODEL` (mặc định `gpt-6-luna`, reasoning `low`, Structured Outputs, `store: false`, `max_output_tokens` 1200). Giọng nói: Realtime transcription `OPENAI_STT_MODEL` (mặc định `gpt-live-transcribe`, `turn_detection: null`, tiếng Việt). |

Không có fallback sang model đắt hơn. Lỗi key/quyền (401/403/404) không retry; lỗi mạng/timeout retry tối đa một lần khi lượt còn hiện hành.

Nối điện thoại qua USB:

```powershell
adb reverse tcp:8080 tcp:8080
# Từ flutter_app; URL mặc định đã là http://127.0.0.1:8080
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

## Hợp đồng

| Giao diện | Chức năng |
| --- | --- |
| `GET /health` | Trạng thái, chế độ, model, giới hạn |
| `POST /v1/smart/sessions` | Tạo phiên từ `today`, danh sách hồ sơ (`id`, quan hệ, tuổi; không nhận tên/SĐT) và ngữ cảnh đã chọn. Trả `session_id`, `token`, `mode`, `voice_available`, câu trả lời đầu tiên |
| `POST /v1/smart/sessions/:id/turns` | `{kind: text, text}` cho lượt nhập tay; `{kind: choice\|edit, field, value}` cho lựa chọn nhanh và sửa tay. Header `x-session-token` |
| `DELETE /v1/smart/sessions/:id` | Đóng phiên, hủy tác vụ đang chạy, xóa dữ liệu tạm |
| WebSocket `/v1/smart/sessions/:id/audio?token=` | App gửi PCM16 mono 24 kHz (binary) và `audio.start`, `turn.commit`, `turn.cancel`, `audio.stop`. Server trả `session.ready`, `transcript.delta`, `transcript.final`, `turn.result`, `turn.empty`, `limit.warning`, `audio.stopped`, `session.error` |

Mỗi câu trả lời có `draft_version`, `status` (`ask`, `ready`, `urgent`, `fallback`, `superseded`), `fields` cùng nguồn của từng trường (`context`, `ai`, `suggested`, `choice`, `manual`), một `question` với lựa chọn nhanh, `notice`, `error` và `catalog_version`.

Quy tắc điều phối nằm trong `src/orchestrator.js`:

- Model chỉ đề xuất giá trị. Server từ chối ID ngoài [catalog](catalog/catalog.json), ngày ngoài 6 ngày đặt được và dữ liệu sai dạng.
- Lượt mới hủy lượt đang xử lý và chạy lại trên tất cả câu chưa xử lý, nên không mất lời nói và không áp kết quả cũ.
- Kết quả model không ghi đè trường người dùng chọn hoặc sửa tay sau câu nói tương ứng.
- Đổi người khám xóa mô tả sức khỏe và gợi ý khoa của người trước. Kiểm tra tuổi khoa Nhi và cơ sở nhận BHYT; không tự đổi hình thức khám.
- Mỗi lượt hỏi một trường còn thiếu; sau hai lần hỏi cùng trường, app gợi ý đặt lịch từng bước.
- Dấu hiệu cần cấp cứu (`urgent`) dừng nhánh đặt lịch thường. Danh sách cụm từ ở chế độ mock chỉ là mẫu, **chưa được chuyên môn duyệt**.

Giờ khám, slot và phí vẫn do `BookingRepository` mô phỏng trong app kiểm tra (đóng vai hệ thống lịch bệnh viện). Catalog dùng chung được test Flutter đối chiếu với `BookingCatalog` để phát hiện lệch.

## Cơ sở dữ liệu phòng khám

Từ bước 13 (web bác sĩ), backend có cơ sở dữ liệu cho lịch khám, đồng ý chia sẻ, nhật ký thuốc, tóm tắt và kết quả khám. Bản dev dùng SQLite qua `node:sqlite` có sẵn trong Node 22 (không cần cài thêm, Node in cảnh báo "experimental" khi mở). Bản chạy thử với phòng khám sẽ dùng PostgreSQL.

- `src/db/migrations.js`: schema. Tên bảng theo tài nguyên FHIR tương ứng (`appointment`, `consent`, `visit_result`, `audit_event`…). Chỉ thêm migration mới, không sửa migration đã phát hành.
- `src/db/index.js`: `openDatabase(path)` tạo file và chạy migration theo `PRAGMA user_version`; `transaction(db, fn)`.
- Kết quả khám đã gửi không bị sửa: sửa là thêm phiên bản mới kèm lý do. Tóm tắt cũng không ghi đè.

## Web bác sĩ

Từ bước 14, backend phục vụ web bác sĩ và API phòng khám ([CLINIC-API.md](CLINIC-API.md)), mã nằm ở `src/clinic/`.

```powershell
# Chạy từ backend; tạo lại data/clinic.db với dữ liệu mẫu theo ngày hôm nay
npm run seed
# Build web (từ doctor_web): flutter build web --base-href /doctor/ --no-web-resources-cdn
npm start
```

Mở `http://localhost:8080/doctor/`, đăng nhập `bs.ha@anbinh.test`, mật khẩu `medicapp-demo` (đổi bằng `DEMO_PASSWORD` trước khi seed). Hàng chờ có 6 người bệnh của bản bấm thử, lịch vào ngày chạy seed; seed lại mỗi ngày demo, hoặc đặt `SEED_TODAY=yyyy-MM-dd`.

- `CLINIC_DB` (mặc định `data/clinic.db`), `DOCTOR_WEB_DIR` (mặc định `../doctor_web/build/web`). Thư mục `data/` không vào git.
- Phiên bác sĩ trong cookie `mc_staff` (HttpOnly, SameSite=Strict), chỉ ở bộ nhớ: 30 phút không thao tác hoặc 12 giờ thì hết; khởi động lại server phải đăng nhập lại. Sai mật khẩu 5 lần khóa 15 phút.
- Mỗi lần mở hồ sơ, đánh giá tóm tắt, đổi trạng thái lượt khám ghi một dòng `audit_event`. Log chỉ có tên sự kiện, không có tên người bệnh, triệu chứng, mật khẩu hay token.
- Bước 15: bác sĩ soạn chẩn đoán và đơn thuốc (danh mục mẫu trong `catalog/clinic-catalog.json`, chưa được duyệt), ký gửi thì có **mã nhận kết quả** dạng `XXXX-XXXX-XX`. Người bệnh nhập mã trong app (`GET /v1/results/claim/:code`, không cần đăng nhập, 10 lần/phút mỗi IP, mã hết hạn sau 30 ngày). Kết quả đã gửi không sửa được, chỉ mở bản sửa mới kèm lý do.
- Seed in mã của Trần Văn Minh (`claimCodeP1`); đặt `SEED_CLAIM_CODE=K7MQ-4XR2-9D` để mã cố định khi demo.
- Chạy `flutter run -d web-server --web-port 5000` thì đặt `DOCTOR_WEB_DEV_ORIGIN=http://localhost:5000` trong `.env` để bật CORS cho đúng origin đó.

## Giới hạn và dữ liệu

Cấu hình trong `.env` (xem `.env.example`): 60 giây/lượt nói, 5 phút micro/phiên, 12 lượt gọi model/phút/phiên, timeout model 20 giây, phiên rảnh 30 phút, tối đa 20 phiên, một kết nối micro mỗi phiên, dừng khi bộ đệm gửi lên nhà cung cấp vượt 1 MiB.

Phiên chỉ ở bộ nhớ, mất khi đóng hoặc khởi động lại server. Audio chỉ chuyển tiếp, không ghi file. Log chỉ có sự kiện, mã lỗi, độ trễ, usage và request ID; không có key, transcript, triệu chứng, hồ sơ hay token.

## Kiểm tra

```powershell
npm test
```

58 test (`node --test`) với provider giả: điều phối hội thoại theo AC01–AC17, máy chủ HTTP, relay audio và giới hạn, xử lý lỗi Responses API, cơ sở dữ liệu, và API phòng khám (đăng nhập, khóa tài khoản, hàng chờ, đồng ý chia sẻ, hồ sơ, audit, phạm vi phòng khám, phục vụ web, CORS, đơn thuốc, gửi và sửa kết quả, mã nhận kết quả). Test Flutter `test/smart/backend_contract_test.dart` chạy server thật ở chế độ mock nếu đã `npm ci`.

**Chưa kiểm chứng:** chưa gọi OpenAI bằng key thật, chưa đo chất lượng nhận tiếng Việt, độ trễ hay chi phí, chưa thử trên OPPO. Đây là prototype dùng dữ liệu minh họa, không phải công cụ phân luồng y khoa và không phải kiến trúc production (phía app chưa có xác thực người dùng, quota theo người dùng; chưa có HTTPS).
