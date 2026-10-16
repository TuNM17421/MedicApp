# Hồ sơ đánh giá tác động xử lý dữ liệu cá nhân — chạy thử MedicApp tại phòng khám đối tác (BẢN NHÁP)

> **Đây là bản nháp làm việc, không phải ý kiến pháp lý.** Bản này do nhóm dự án soạn từ mã nguồn hiện có (ngày 16/10/2026, bước 18), để chủ dự án và phòng khám cùng hoàn thiện. Văn bản áp dụng theo kế hoạch đã duyệt: **Luật Bảo vệ dữ liệu cá nhân (2025)** và **Nghị định 356/2025/NĐ-CP**. Phòng khám hoặc cố vấn pháp lý **phải đối chiếu mẫu hồ sơ, nội dung bắt buộc, thời hạn và nơi nộp** với các văn bản đó trước khi nộp. Chỗ nào yêu cầu cụ thể của luật quyết định nội dung, tài liệu ghi "cần đối chiếu điều khoản" thay vì đoán số điều.
>
> Mọi mô tả "hệ thống làm gì" đều dẫn tới file mã nguồn (đường dẫn tính từ `05-prototype/`). Phần đánh dấu **[bước 18]** là việc đang được thêm trong bước này; cần kiểm tra lại khi bước 18 xong.

## 1. Phạm vi

- **Hoạt động xử lý:** người bệnh dùng app MedicApp đăng nhập bằng số điện thoại, trả lời câu hỏi trước khám, chia sẻ (tùy chọn) nhật ký uống thuốc và thuốc tự dùng với phòng khám cho từng lượt khám; hệ thống tạo tóm tắt trước khám (có thể dùng dịch vụ AI ở nước ngoài); bác sĩ xem trên web, kê đơn và gửi kết quả về app.
- **Thời gian:** chạy thử 2 tuần với 1 bác sĩ, sau đó mở cho cả khoa (xem `docs/ke-hoach-chay-thu.md`).
- **Ngoài phạm vi bản này:** tính năng Đặt lịch thông minh (Smart Scheduling) của app cũng gửi lời nói/mô tả sức khỏe tới OpenAI (`backend/README.md`, `src/orchestrator.js`, `src/stt.js`). Nếu bật tính năng đó cho người bệnh của phòng khám trong thời gian chạy thử, cần đánh giá bổ sung.

## 2. Các bên và vai trò

Vai trò pháp lý (bên kiểm soát, bên xử lý, bên kiểm soát và xử lý…) phải xác định theo định nghĩa của luật — **cần đối chiếu điều khoản**. Bảng dưới là đề xuất để thảo luận.

| Bên | Làm gì trong hệ thống | Vai trò đề xuất (cần xác nhận) |
| --- | --- | --- |
| Phòng khám đối tác | Quyết định mục đích khám chữa bệnh; bác sĩ xem dữ liệu, kê đơn, gửi kết quả; quản trị tạo tài khoản bác sĩ | Bên kiểm soát dữ liệu của người bệnh tại phòng khám |
| Đơn vị vận hành MedicApp (chủ dự án) | Viết và vận hành app, máy chủ, cơ sở dữ liệu, sao lưu | Bên xử lý cho phòng khám (máy chủ); với dữ liệu lưu trên điện thoại, app không gửi đi đâu (xem mục 6) |
| Nhà cung cấp AI (OpenAI, Responses API) | Nhận câu trả lời trước khám đã che thông tin định danh, trả về bản tóm tắt | Bên xử lý (thứ cấp); ở nước ngoài → chuyển dữ liệu ra nước ngoài |
| Nhà cung cấp SMS | Gửi mã OTP | **Chưa chọn** (xem mục 10) |
| Nơi đặt máy chủ (trong nước hoặc đám mây) | Lưu cơ sở dữ liệu và bản sao lưu | **Chưa quyết định** (xem mục 10) |

Cần có hợp đồng/thỏa thuận xử lý dữ liệu giữa phòng khám và đơn vị vận hành, và giữa đơn vị vận hành và OpenAI. Nội dung bắt buộc của các thỏa thuận này: cần đối chiếu điều khoản.

## 3. Mục đích xử lý

| # | Mục đích | Dữ liệu dùng |
| --- | --- | --- |
| M1 | Đăng nhập người bệnh, gắn lượt khám với người bệnh | Số điện thoại, mã OTP (băm), phiên |
| M2 | Bác sĩ chuẩn bị trước buổi khám | Câu trả lời trước khám, thuốc tự dùng, nhật ký liều 30 ngày (chỉ khi người bệnh đồng ý) |
| M3 | Tóm tắt trước khám và cờ dấu hiệu cần chú ý | Câu trả lời trước khám (đã che định danh) |
| M4 | Kê đơn, gửi kết quả khám về app, nhắc uống thuốc | Chẩn đoán, đơn thuốc, lời dặn, ngày tái khám |
| M5 | Bảo đảm an toàn, truy vết truy cập | Nhật ký `audit_event`, log kỹ thuật không có nội dung bệnh |
| M6 | Đo kết quả chạy thử | Số đếm và thời gian lấy từ `audit_event`, `visit_summary`, `visit_result` **[bước 18: trang chỉ số cho quản trị]** |

Không dùng dữ liệu cho quảng cáo, không bán, không huấn luyện model (gửi OpenAI với `store: false`, xem mục 5).

## 4. Danh mục dữ liệu

Cơ sở pháp lý ghi "đồng ý" nghĩa là đồng ý rõ ràng của người bệnh qua màn "Chia sẻ với phòng khám". Với dữ liệu do phòng khám tự ghi khi khám chữa bệnh, cơ sở pháp lý có thể khác (nghĩa vụ hồ sơ bệnh án, hợp đồng dịch vụ…) — **cần đối chiếu điều khoản**. Cột "Lưu đến khi" phản ánh **mã hiện tại**: chưa có tác vụ xóa tự động nào.

| Dữ liệu | Nguồn | Nơi lưu (bảng, file) | Ai thấy | Lưu đến khi (theo mã) | Cơ sở pháp lý đề xuất |
| --- | --- | --- | --- | --- | --- |
| Họ tên, ngày sinh, giới, địa chỉ, mã người bệnh, cân nặng | Phòng khám | `patient` (`src/db/migrations.js`) | Bác sĩ cùng phòng khám (`src/clinic/api.js`, mọi truy vấn lọc `clinic_id`) | Không xóa | Cần đối chiếu điều khoản |
| Mã thẻ BHYT | Phòng khám | `patient.insurance_code` | Web chỉ hiện 4 số cuối (`maskInsurance`, `api.js`) | Không xóa | Cần đối chiếu điều khoản |
| Dị ứng, bệnh đang theo dõi | Phòng khám | `patient.allergy`, `patient.conditions` | Bác sĩ cùng phòng khám | Không xóa | Cần đối chiếu điều khoản |
| Số điện thoại | Phòng khám nhập; người bệnh dùng để đăng nhập | `patient.phone` (migration bước 16) | Bác sĩ; log chỉ có dạng che `09•••••482` | Không xóa | Cần đối chiếu điều khoản |
| Mã OTP | Server sinh | `patient_otp`, chỉ lưu HMAC-SHA256 (`src/clinic/patient.js`) | Không ai đọc được mã gốc | 5 phút; xóa khi dùng hoặc sai 5 lần | Phục vụ đăng nhập |
| Phiên người bệnh | Server sinh | `patient_session`, chỉ lưu SHA-256 của token | — | 30 ngày, thu hồi khi đăng xuất | Phục vụ đăng nhập |
| Lịch khám | Phòng khám | `appointment` | Bác sĩ; người bệnh có số điện thoại đó | Không xóa | Cần đối chiếu điều khoản |
| Bản ghi đồng ý (phạm vi, phiên bản lời văn, thời điểm) | Người bệnh | `consent` | Bác sĩ thấy trạng thái; người bệnh thấy trên app | Không xóa (bằng chứng đồng ý) | Nghĩa vụ chứng minh đồng ý — cần đối chiếu điều khoản |
| **Câu trả lời trước khám** (triệu chứng, diễn biến, câu hỏi) — dữ liệu sức khỏe | Người bệnh, từ app | `intake_answer` | Bác sĩ, chỉ khi đồng ý còn hiệu lực có `intake` | Không xóa; rút/hết hạn thì **ẩn**, không xóa | **Đồng ý rõ ràng** |
| **Thuốc tự dùng** — dữ liệu sức khỏe | Người bệnh | `self_medication` | Bác sĩ, khi đồng ý có `self_meds` | Như trên | **Đồng ý rõ ràng** |
| **Nhật ký liều thuốc** (đã uống/bỏ, lý do) — dữ liệu sức khỏe | Người bệnh | `dose_event` | Bác sĩ, khi đồng ý có `dose_log`, chỉ 30 ngày trước ngày khám | Như trên | **Đồng ý rõ ràng** |
| **Tóm tắt trước khám, cờ dấu hiệu** | Server (AI hoặc quy tắc) | `visit_summary` (không ghi đè, mỗi lần một dòng) | Bác sĩ, khi đồng ý có `intake` | Không xóa | Theo đồng ý `intake` |
| Đánh giá tóm tắt (Đúng/Sai) | Bác sĩ | `visit_summary.feedback` | Bác sĩ, quản trị | Không xóa | Phục vụ chất lượng — cần đối chiếu |
| **Chẩn đoán, đơn thuốc, lời dặn, ghi chú nội bộ** | Bác sĩ | `visit_result` (bản đã gửi không sửa, sửa là bản mới có lý do) | Bác sĩ; người bệnh thấy bản đã gửi (không thấy ghi chú nội bộ) | Không xóa | Khám chữa bệnh — cần đối chiếu |
| Đợt thuốc theo đơn | Server tạo khi gửi kết quả | `med_course` | Bác sĩ (theo đồng ý `dose_log`), app | Không xóa | Như trên |
| Mã nhận kết quả | Server sinh | `appointment.claim_code` | Người có mã | Hết hạn 30 ngày sau lần gửi đầu (`CLAIM_DAYS`, `api.js`) | Phục vụ nhận kết quả |
| Tài khoản bác sĩ (email, tên, số chứng chỉ, mật khẩu băm) | Quản trị phòng khám **[bước 18]** | `practitioner` | Quản trị | Không xóa | Hợp đồng lao động/dịch vụ — cần đối chiếu |
| Nhật ký truy cập | Server | `audit_event` (thời điểm, người làm, hành động, mã người bệnh/lượt khám, IP; `detail` không có lời người bệnh) | Quản trị **[bước 18: xem theo người bệnh]** | Không xóa | Bảo đảm an toàn |
| Log kỹ thuật | Server | stdout | Người vận hành | Theo cấu hình máy chủ | Chỉ có tên sự kiện, mã lỗi, độ trễ, số đếm (`api.js`, `summary/worker.js`) |

**Trên điện thoại** (không do máy chủ lưu): hồ sơ gia đình (họ tên, năm sinh, giới, số CCCD, địa chỉ, bệnh đang theo dõi), kết quả khám, nhật ký liều, hàng chờ gửi (`outbox`) — chỉ lưu khi chủ tài khoản đồng ý ở màn "Lưu dữ liệu sức khỏe", mã hóa AES-256-GCM, khóa trong Android Keystore (`flutter_app/README.md` bước 10, `lib/features/consent/health_consent_page.dart`, `lib/features/sharing/domain/outbox.dart`).

## 5. Dữ liệu nhạy cảm

- Câu trả lời trước khám, thuốc tự dùng, nhật ký liều, tóm tắt, chẩn đoán, đơn thuốc, dị ứng, bệnh nền là **dữ liệu sức khỏe**, thuộc nhóm dữ liệu cá nhân nhạy cảm. App đã nói rõ điều này với người dùng ("Thông tin sức khỏe là dữ liệu cá nhân nhạy cảm theo Nghị định 356/2025/NĐ-CP", `health_consent_page.dart`).
- Mã BHYT, số CCCD (chỉ trên máy) là dữ liệu định danh; việc xếp loại cụ thể cần đối chiếu điều khoản.
- Người bệnh cao tuổi hoặc người trong gia đình được chủ tài khoản quản lý: app hiện cho chủ tài khoản đồng ý thay cả gia đình. Quy định về đồng ý thay người khác (người cao tuổi, trẻ em) — **cần đối chiếu điều khoản** và phòng khám quyết định cách làm (mục 11).

## 6. Luồng dữ liệu

```
App người bệnh ──(HTTPS*, token Bearer)──> Máy chủ MedicApp ──> CSDL phòng khám (SQLite dev / PostgreSQL pilot)
     │  đồng ý theo lượt khám                    │                     │
     │                                           │                     └─> Sao lưu hằng ngày [bước 18]
     │                                           ├──(chỉ câu trả lời, đã che)──> OpenAI Responses API (nước ngoài)
     │                                           │
Web bác sĩ <──(cookie mc_staff, cùng origin)─────┘
```
\* HTTPS: máy chủ Node không tự làm TLS; cần đặt sau reverse proxy có HTTPS và đặt `HTTPS=1` để cookie có `Secure` (`src/config.js`). Đây là điều kiện tiên quyết của chạy thử.

### 6.1 Từ app lên máy chủ

- Chỉ gửi khi có đồng ý còn hiệu lực đúng phạm vi, nếu không trả `403 consent_required` (`patient.js`, `CLINIC-API.md` "Gửi dữ liệu từ app").
- Dữ liệu chưa gửi được (mất mạng) nằm trong `outbox` trên máy, gửi lại sau (`lib/features/sharing/domain/outbox.dart`).

### 6.2 Chuyển ra nước ngoài: tóm tắt bằng AI

| Câu hỏi | Trả lời theo mã |
| --- | --- |
| Gửi gì? | **Chỉ** các dòng `intake_answer` của một lượt khám: `channel`, `question`, `answer`, với id rút gọn `a1`, `a2`… (`src/summary/pipeline.js` `runSummary`, `src/summary/openai.js` `buildSummaryRequest`) |
| Không gửi gì? | Tên, số điện thoại, mã BHYT, địa chỉ, tuổi, giới, bệnh nền, dị ứng, đơn thuốc, nhật ký liều, mã lượt khám, mã người bệnh |
| Che gì trong lời người bệnh? | Hàm `redact` (`pipeline.js`) thay: họ tên đầy đủ đang lưu → `[tên]`; địa chỉ đang lưu → `[địa chỉ]`; mã BHYT đang lưu và mọi chuỗi dạng 2 chữ + 13 số → `[mã BHYT]`; số điện thoại đang lưu và mọi số dạng `0`/`+84` + 9 số → `[số điện thoại]` |
| Che **không** được gì? | Tên viết tắt/một phần ("bà Lan"), tên người thân, nơi làm việc, ngày sinh, địa chỉ viết khác cách lưu, số CCCD. Nội dung bệnh tất nhiên vẫn được gửi — đó là mục đích. → rủi ro còn lại, xem mục 9 |
| Nhà cung cấp có lưu không? | Request đặt `store: false` (`openai.js`). Chính sách lưu tạm để chống lạm dụng, vùng xử lý và DPA của OpenAI **chưa được xác nhận** (mục 10) |
| Model, giới hạn | `OPENAI_MODEL` (mặc định `gpt-6-luna`), Structured Outputs `strict`, timeout `MODEL_TIMEOUT_MS`, thử lại tối đa 1 lần, không đổi model khác (`openai.js`, `src/config.js`) |
| Khi nào gửi? | Sau khi người bệnh gửi câu trả lời, chờ 3 giây gộp; chỉ khi đồng ý mới nhất còn hiệu lực có `intake`; kiểm tra lại sau khi model trả về, đồng ý bị rút thì bỏ kết quả (`src/summary/worker.js`) |
| Tắt được không? | Có, theo phòng khám (mỗi máy chủ một phòng khám): `CLINIC_AI_SUMMARY=off` (không tóm tắt) hoặc `mock` (quy tắc, không gửi ra ngoài). Mặc định `auto` chạy như `mock` kể cả khi có `OPENAI_API_KEY`; câu trả lời chỉ gửi OpenAI khi đặt rõ `openai` (`src/config.js`). Cấu hình chạy thử vẫn phải ghi rõ giá trị đã chọn |
| Ai kiểm tra kết quả AI? | Code bỏ câu không có nguồn, bỏ cả mục có con số hoặc tên thuốc không có trong câu gốc (`src/summary/guard.js`); cờ dấu hiệu do danh sách cụm từ trong code tìm, không do model (`src/summary/red-flags.js`); web hiện câu gốc cạnh tóm tắt; bác sĩ bấm Đúng/Sai |
| Log có nội dung không? | Không. Log và `audit_event` chỉ có số đếm, mã lỗi, độ trễ, request id (`openai.js`, `worker.js`) |

Thủ tục, hồ sơ đánh giá tác động chuyển dữ liệu ra nước ngoài và nghĩa vụ thông báo: **cần đối chiếu điều khoản** của Luật và Nghị định 356/2025/NĐ-CP. Người bệnh hiện **chưa** được thông báo trên màn chia sẻ rằng câu trả lời được gửi tới dịch vụ AI ở nước ngoài (lời văn ở `clinic_sharing_pages.dart` chỉ nói về phòng khám) — xem mục 10.

### 6.3 Từ máy chủ về app

- Kết quả đã gửi: qua phiên người bệnh (`GET /v1/patient/appointments/:id/result`) hoặc mã nhận kết quả (`GET /v1/results/claim/:code`, không cần đăng nhập, 10 lần/phút/IP). Người có mã (in trên đơn giấy) xem được kết quả trong 30 ngày.

## 7. Cơ chế đồng ý

| Đặc điểm | Theo mã |
| --- | --- |
| Theo từng lượt khám, từng phòng khám | Bảng `consent` gắn `appointment_id`; màn ghi "Chỉ phòng khám này thấy, và chỉ cho lượt khám này" (`clinic_sharing_pages.dart`) |
| Chọn từng phạm vi | 3 ô riêng: Câu trả lời trước khám (`intake`), 30 ngày uống thuốc (`dose_log`), Thuốc tự dùng (`self_meds`) (`sharing_models.dart`) |
| Không đánh dấu sẵn | Lần đầu tập phạm vi rỗng; ô "Tôi đồng ý cho [phòng khám] xem những mục đã chọn ở trên, đến hết ngày …" mặc định chưa đánh dấu; nút chỉ bật khi đã đánh dấu và chọn ít nhất 1 mục (`clinic_sharing_pages.dart`) |
| Thông tin hiển thị | Tên, điện thoại phòng khám; ngày giờ khám; đến ngày nào; cách rút lại |
| Hết hạn | 30 ngày sau giờ khám (lượt cũ: 30 ngày từ lúc đồng ý) (`CONSENT_DAYS`, `patient.js`) |
| Rút lại | Bất kỳ lúc nào trên app; web bác sĩ không còn thấy từ lần tải sau; ghi `consent.revoke`. **Dữ liệu không bị xóa, chỉ bị ẩn** (`CLINIC-API.md`) |
| Bằng chứng | Mỗi lần đồng ý thêm một dòng mới (không sửa), có `wording_version` (hiện là 1), `granted_at`; ghi `audit_event` `consent.grant` |
| Đồng ý lưu trên máy | Tách riêng: màn "Lưu dữ liệu sức khỏe", có ô "Tôi hiểu đây là dữ liệu sức khỏe nhạy cảm và đồng ý lưu trên máy này"; "Ngừng lưu" xóa dữ liệu trên máy (`health_consent_page.dart`) |

Nội dung bắt buộc của thông báo xử lý dữ liệu và hình thức đồng ý hợp lệ: **cần đối chiếu điều khoản**. Tối thiểu cần bổ sung vào lời văn: việc gửi tới dịch vụ AI ở nước ngoài, thời gian lưu, quyền yêu cầu xóa và cách liên hệ (mục 10). Đổi lời văn thì tăng `sharingWordingVersion`.

## 8. Biện pháp bảo vệ đã có

| Biện pháp | Chi tiết | Nguồn |
| --- | --- | --- |
| Mật khẩu bác sĩ băm | scrypt (N=16384, r=8, p=1), salt 16 byte, so sánh thời gian hằng | `src/clinic/auth.js` |
| Khóa tài khoản | Sai 5 lần liên tiếp khóa 15 phút | `auth.js`, `api.js` |
| Phiên bác sĩ | Token 32 byte ngẫu nhiên, cookie `HttpOnly; SameSite=Strict` (+`Secure` khi `HTTPS=1`), hết sau 30 phút không thao tác, tối đa 12 giờ, chỉ trong bộ nhớ | `auth.js` |
| Tài khoản bác sĩ do quản trị tạo | **[bước 18]** — thay cho tài khoản tạo bằng seed | kế hoạch bước 18 |
| OTP người bệnh | 6 số, 5 phút, tối đa 5 lần nhập, dùng một lần, lưu HMAC-SHA256 với `PATIENT_OTP_PEPPER` (bắt buộc khi production); 3 lần xin/10 phút/số, 10 lần/10 phút/IP; trả lời giống nhau dù số có hay không | `patient.js`, `src/config.js` |
| Phiên người bệnh | Token 32 byte, chỉ lưu SHA-256, 30 ngày, thu hồi được | `patient.js` |
| Cách ly phòng khám | Mọi truy vấn của bác sĩ lọc theo `clinic_id`; khác phòng khám trả `404` | `api.js` |
| Phân quyền theo đồng ý | Dữ liệu chia sẻ chỉ trả khi đồng ý mới nhất còn hiệu lực đúng phạm vi | `api.js` (`has(...)`), `patient.js` |
| Nhật ký truy cập | `audit_event` cho xem hồ sơ, xem lịch sử, đánh giá tóm tắt, đổi trạng thái, lưu nháp/gửi/sửa đơn, đồng ý/rút, gửi dữ liệu, xem/nhận kết quả, tạo tóm tắt; có IP. **[bước 18]**: xem theo người bệnh | `api.js`, `patient.js`, `worker.js` |
| Kết quả không sửa ngầm | Bản đã gửi không sửa; sửa là bản mới có lý do | `visit_result`, `CLINIC-API.md` |
| Giới hạn đầu vào | Thân 16 KiB (512 KiB khi gửi dữ liệu), kiểm tra kiểu/độ dài, 60 lần gửi/phút/token, mã nhận 10 lần/phút/IP | `src/http.js`, `patient.js`, `api.js` |
| Lỗi không lộ thông tin | Không có stack trace; lỗi trả mã trường, không trả giá trị | `src/http.js` |
| Log không có nội dung | Không tên, triệu chứng, mật khẩu, token | `backend/README.md`, `api.js` |
| Header bảo mật | `no-store` cho JSON; web bác sĩ có `nosniff`, `no-referrer`, `X-Frame-Options: DENY`; web không tải CanvasKit từ CDN ngoài | `src/http.js`, `src/clinic/static.js`, `doctor_web/README.md` |
| Che BHYT | Web và kết quả chỉ hiện 4 số cuối | `api.js` |
| Mã khóa API | Chỉ ở `.env` máy chủ, không vào app hay log | `src/config.js`, `backend/README.md` |
| Bind localhost | Server chỉ nghe `127.0.0.1` trừ khi đặt `ALLOW_NON_LOCAL_HOST=1` (để sau reverse proxy) | `src/config.js` |
| Sao lưu | **[bước 18]** sao lưu cơ sở dữ liệu hằng ngày; cần thử khôi phục trước chạy thử | kế hoạch bước 18 |
| Trên máy | AES-256-GCM, khóa Android Keystore, chỉ khi đồng ý | `flutter_app/README.md` |

Chưa có: mã hóa cơ sở dữ liệu ở mức đĩa/cột (phụ thuộc máy chủ), xác thực hai lớp cho bác sĩ, chính sách thời gian lưu, cảnh báo truy cập bất thường. Yêu cầu tối thiểu về biện pháp kỹ thuật theo Nghị định: cần đối chiếu điều khoản.

## 9. Rủi ro và biện pháp giảm thiểu

Mã R1–R6 lấy từ kế hoạch đã duyệt; D1–D8 là rủi ro bổ sung của bản đánh giá này. Mức độ là đề xuất, cần phòng khám thống nhất.

| Mã | Rủi ro | Mức | Đã làm | Còn phải làm |
| --- | --- | --- | --- | --- |
| R1 | Tài khoản người bệnh giả lập | Trung bình | Đăng nhập bằng số điện thoại + OTP (bước 16) | **Chưa có nhà cung cấp SMS**; production đặt `PATIENT_OTP_MODE=off` thì không đăng nhập được |
| R3 | AI tóm tắt sai hoặc thêm ý | Cao | Chỉ tóm tắt lời người bệnh, bắt buộc nguồn, bỏ mục có số/thuốc ngoài nguồn, cờ do quy tắc, nút Sai, eval 30 ca | Chưa chạy với key thật; bác sĩ đọc 10 tóm tắt; danh sách cờ và tên thuốc chưa duyệt |
| R4 | Gửi dữ liệu sức khỏe ra AI nước ngoài | Cao | Không gửi tên, SĐT, BHYT, địa chỉ; che trong câu trả lời; `store: false`; tắt được theo phòng khám | DPA/vùng xử lý OpenAI; thông báo cho người bệnh; thủ tục chuyển dữ liệu ra nước ngoài (cần đối chiếu điều khoản); che tên một phần |
| R5 | Bác sĩ nhập đơn hai nơi, sai lệch giữa hai hệ thống | Trung bình | Chạy thử chỉ nhập ở web MedicApp, đơn ngắn | Thống nhất đơn nào là bản chính thức |
| R6 | In đơn sai khổ/trình duyệt khác nhau | Thấp | In bằng PDF A4 một trang | Thử trên máy in thật của phòng khám |
| R2 | Mẫu đơn đổi theo TT 26/2025/TT-BYT | Thấp (với dữ liệu) | Mẫu dựng từ cấu hình trường | Phòng khám xác nhận mẫu |
| D1 | Truy cập trái phép bằng tài khoản bác sĩ | Cao | Băm mật khẩu, khóa, phiên ngắn, audit | Tài khoản do quản trị tạo, không dùng chung; xem nhật ký định kỳ |
| D2 | Lộ đường truyền | Cao | Cookie `Secure` khi `HTTPS=1` | **Bắt buộc HTTPS** trước chạy thử |
| D3 | Mất dữ liệu | Trung bình | — | Sao lưu hằng ngày, thử khôi phục, bản sao lưu cũng phải bảo vệ (mã hóa, giới hạn người truy cập) |
| D4 | Rút đồng ý nhưng dữ liệu vẫn nằm trong CSDL | Trung bình | Ẩn ngay | Luồng xóa theo yêu cầu (mục 10) |
| D5 | Mã nhận kết quả bị người khác thấy (đơn giấy) | Thấp–TB | 50 bit ngẫu nhiên, 10 lần/phút/IP, hết hạn 30 ngày | Dặn người bệnh giữ đơn; cân nhắc tắt mã khi đã đăng nhập |
| D6 | Một số điện thoại dùng chung trong gia đình thấy lượt khám của nhau | Trung bình | Phiên theo số điện thoại (`CLINIC-API.md` bước 16) | Phòng khám quyết định chính sách số chung |
| D7 | Cờ dấu hiệu sót hoặc thừa → chậm xử trí | Cao | Khi không chắc thì gắn cờ; không thay phán đoán bác sĩ | Bác sĩ duyệt danh sách trước chạy thử |
| D8 | Log/máy chủ bên thứ ba (đám mây) truy cập dữ liệu | Trung bình | Log không có nội dung | Quyết định nơi đặt máy chủ, hợp đồng với nhà cung cấp |

## 10. Khoảng trống trước khi chạy thử

| # | Khoảng trống | Ảnh hưởng | Đề xuất xử lý | Người phụ trách |
| --- | --- | --- | --- | --- |
| G1 | Chưa có nhà cung cấp SMS cho OTP | Người bệnh không đăng nhập được ở production | Chọn nhà cung cấp trong nước, ký thỏa thuận xử lý dữ liệu; hoặc tạm dùng mã nhận kết quả và nhân viên hỗ trợ | Chủ dự án |
| G2 | Rút đồng ý không xóa dữ liệu đã gửi | Không đáp ứng được yêu cầu xóa | Thêm xóa (hoặc xóa sau N ngày) khi rút; cần đối chiếu điều khoản về quyền xóa | Chủ dự án |
| G3 | Chưa có luồng yêu cầu xóa/xem/sửa dữ liệu của người bệnh | Không đáp ứng quyền của chủ thể dữ liệu | Tối thiểu: quy trình thủ công (người bệnh liên hệ phòng khám, quản trị xóa, ghi `audit_event`), thời hạn trả lời cần đối chiếu điều khoản | Phòng khám + chủ dự án |
| G4 | Danh sách dấu hiệu cần chú ý chưa được duyệt (`red-flags.json`, `reviewed: false`); tên thuốc cũng vậy | Cờ sai | Bác sĩ phòng khám duyệt, ghi phiên bản đã duyệt | Bác sĩ trưởng khoa |
| G5 | DPA và vùng xử lý của OpenAI chưa chốt | Không chứng minh được bảo vệ khi chuyển ra nước ngoài | Ký DPA, xác nhận chế độ lưu dữ liệu, ghi lại; nếu không xong thì chạy thử với `CLINIC_AI_SUMMARY=mock` hoặc `off` | Chủ dự án |
| G6 | Chưa quyết định nơi đặt máy chủ | Không xác định được bên xử lý, luồng ra nước ngoài thêm | Phòng khám chọn trong nước hay đám mây; ghi vào hồ sơ này | Phòng khám |
| G7 | Lời văn đồng ý chưa nói về AI ở nước ngoài, thời gian lưu, quyền xóa, liên hệ | Đồng ý có thể không đủ thông tin | Sửa lời văn, tăng `sharingWordingVersion` | Chủ dự án + pháp lý |
| G8 | Chưa có chính sách thời gian lưu; mã không xóa tự động | Lưu quá mục đích | Phòng khám quyết định thời hạn từng nhóm dữ liệu | Phòng khám |
| G9 | Che định danh không bắt được tên một phần, tên người thân, CCCD | Lộ định danh ra AI | Bổ sung mẫu che; nhắc trong câu hỏi trước khám "không cần ghi tên" | Chủ dự án |
| G10 | Đồng ý thay người nhà (người cao tuổi) | Đồng ý có thể không hợp lệ | Cần đối chiếu điều khoản; phòng khám quyết định | Pháp lý |
| G11 | Bước 18 chưa xong: tài khoản do quản trị tạo, nhật ký theo người bệnh, sao lưu hằng ngày, HTTPS | Thiếu biện pháp cơ bản | Kiểm tra trong danh sách điều kiện của `ke-hoach-chay-thu.md` | Chủ dự án |
| G12 | Chưa có quy trình thông báo khi xảy ra sự cố lộ dữ liệu | Chậm thông báo | Dùng quy trình ở `ke-hoach-chay-thu.md` mục 8; thời hạn và cơ quan nhận thông báo cần đối chiếu điều khoản | Phòng khám + chủ dự án |

## 11. Câu hỏi cho phòng khám

1. Phòng khám đang dùng phần mềm HIS nào? Có xuất lịch hẹn và nhập đơn qua API không?
2. Bác sĩ và khoa nào chạy thử? Bao nhiêu bác sĩ khi mở cho cả khoa?
3. Máy in và khổ giấy dùng in đơn?
4. Ai duyệt danh sách dấu hiệu cần chú ý và bộ câu hỏi trước khám? Bao giờ xong?
5. Máy chủ đặt ở đâu: trong nước (phòng khám/nhà cung cấp nào) hay đám mây?
6. Phòng khám đồng ý dùng dịch vụ AI ở nước ngoài trong chạy thử, hay chỉ dùng chế độ quy tắc (`mock`) / tắt?
7. Ai ở phòng khám là đầu mối bảo vệ dữ liệu cá nhân, và ai làm quản trị tạo tài khoản bác sĩ?
8. Thời gian lưu mong muốn cho: câu trả lời trước khám, nhật ký liều, tóm tắt, kết quả khám, nhật ký truy cập, bản sao lưu?
9. Khi người bệnh rút đồng ý hoặc yêu cầu xóa: xóa ngay, hay giữ phần đã dùng để khám (ví dụ tóm tắt bác sĩ đã đọc) theo quy định hồ sơ bệnh án?
10. Chính sách với số điện thoại dùng chung trong gia đình và đồng ý thay người cao tuổi?
11. Đơn trên MedicApp có phải là đơn chính thức không, hay phòng khám vẫn in/nhập đơn trong HIS?
12. Hồ sơ này cần nộp cho cơ quan nào, theo mẫu nào, khi nào — phòng khám/cố vấn pháp lý xác nhận (cần đối chiếu điều khoản).

## 12. Kiểm tra trước khi ký duyệt hồ sơ

- [ ] Bác sĩ phòng khám A không đọc được hồ sơ phòng khám B (test cách ly, kế hoạch §8).
- [ ] Dữ liệu đã rút đồng ý không trả về web bác sĩ (kế hoạch §8).
- [ ] Đã đọc lại bảng mục 4 với cấu trúc CSDL sau bước 18 (bảng mới, nếu có).
- [ ] Ghi giá trị `CLINIC_AI_SUMMARY`, `OPENAI_MODEL`, nơi đặt máy chủ thực tế.
- [ ] Phòng khám/cố vấn pháp lý đã đối chiếu với Luật và Nghị định 356/2025/NĐ-CP.

| Người soạn | Phòng khám xác nhận | Cố vấn pháp lý | Ngày |
| --- | --- | --- | --- |
| | | | |
