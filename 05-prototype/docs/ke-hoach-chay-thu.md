# Kế hoạch chạy thử MedicApp tại phòng khám đối tác

Tài liệu vận hành cho bước 18. Theo kế hoạch đã duyệt: **chạy thử 2 tuần với 1 bác sĩ, rồi mở cho cả khoa**, đo 4 chỉ số. Hồ sơ dữ liệu đi kèm: [danh-gia-tac-dong-du-lieu.md](danh-gia-tac-dong-du-lieu.md). Các ngưỡng số trong tài liệu này là **đề xuất**, cần phòng khám và chủ dự án thống nhất trước ngày 1.

## 1. Phạm vi chạy thử

| | Giai đoạn 1 | Giai đoạn 2 |
| --- | --- | --- |
| Thời gian | 2 tuần (10 ngày làm việc) | Từ khi đạt tiêu chí mở rộng (mục 7), đề xuất 4 tuần |
| Ai dùng | 1 bác sĩ, 1 quản trị phòng khám | Cả khoa |
| Người bệnh | Người bệnh có lịch khám với bác sĩ đó, có điện thoại Android, đồng ý tham gia | Người bệnh của khoa |
| Việc làm trên MedicApp | Người bệnh: đăng nhập, câu hỏi trước khám, chia sẻ; bác sĩ: đọc tóm tắt, kê đơn, gửi kết quả | Như giai đoạn 1 |
| Không làm | Không thay HIS; không dùng cho cấp cứu; không bật Đặt lịch thông minh | |

Đơn thuốc: trong chạy thử chỉ nhập ở web MedicApp với đơn ngắn (R5). Phòng khám quyết định đơn nào là bản chính thức (câu hỏi 11 trong hồ sơ dữ liệu).

## 2. Vai trò

| Vai trò | Ai | Việc |
| --- | --- | --- |
| Chủ dự án (vận hành MedicApp) | | Máy chủ, cấu hình, sao lưu, xuất chỉ số, sửa lỗi, trực sự cố |
| Quản trị phòng khám | | Tạo/khóa tài khoản bác sĩ, xem nhật ký truy cập, đầu mối dữ liệu cá nhân |
| Bác sĩ chạy thử | | Dùng web khi khám, bấm Đúng/Sai cho tóm tắt, ghi nhận xét, điền phiếu góp ý |
| Bác sĩ duyệt danh sách dấu hiệu | (có thể là trưởng khoa) | Duyệt `red-flags.json` và bộ câu hỏi trước khám |
| Nhân viên tiếp đón | | Giới thiệu app, hỗ trợ đăng nhập, trả lời câu hỏi về chia sẻ dữ liệu |
| Người quyết định mở rộng | Trưởng khoa + chủ dự án | Họp go/no-go cuối tuần 2 |

## 3. Điều kiện trước ngày 1

Tất cả phải ✓ trước khi người bệnh thật dùng. Mục nào chưa xong thì lùi ngày bắt đầu.

### Máy chủ và bảo mật

- [ ] Máy chủ đặt ở nơi phòng khám đã chọn (trong nước/đám mây), ghi vào hồ sơ dữ liệu.
- [ ] HTTPS qua reverse proxy, chứng chỉ hợp lệ; backend đặt `HTTPS=1` (cookie `Secure`), `NODE_ENV=production`, `ALLOW_NON_LOCAL_HOST` chỉ khi cần cho proxy (`backend/src/config.js`).
- [ ] Cơ sở dữ liệu PostgreSQL cho chạy thử (bản dev là SQLite, `backend/README.md`); không dùng dữ liệu seed.
- [ ] `PATIENT_OTP_PEPPER` là giá trị bí mật mới; không đặt `DEMO_OTP`.
- [ ] Đăng nhập người bệnh: đã có nhà cung cấp SMS, **hoặc** thống nhất phương án tạm (chỉ dùng mã nhận kết quả in trên đơn). Với `NODE_ENV=production` mà chưa có SMS, `PATIENT_OTP_MODE=off` → không đăng nhập được, không có câu hỏi trước khám và chia sẻ.
- [ ] Ghi rõ `CLINIC_AI_SUMMARY`: `openai` chỉ khi DPA/vùng xử lý của OpenAI đã chốt; nếu chưa thì `mock` (không gửi ra ngoài) hoặc `off`. Lưu ý mặc định `auto` tự dùng OpenAI khi có key.
- [ ] Sao lưu hằng ngày chạy được **và đã thử khôi phục** một bản sao lưu vào máy khác, kiểm tra mở được hồ sơ.
- [ ] Bản sao lưu được bảo vệ (mã hóa hoặc chỉ người vận hành truy cập).
- [ ] Test cách ly: tài khoản phòng khám A không đọc được hồ sơ phòng khám B; dữ liệu đã rút đồng ý không trả về.

### Tài khoản

- [ ] Tài khoản bác sĩ do quản trị phòng khám tạo (không dùng `bs.ha@anbinh.test` hay tài khoản seed), mỗi người một tài khoản, không dùng chung.
- [ ] Bác sĩ đã đăng nhập thử, đổi mật khẩu (nếu có chức năng), biết khóa 15 phút sau 5 lần sai và hết phiên sau 30 phút không thao tác.
- [ ] Quản trị đã mở thử nhật ký truy cập theo một người bệnh thử và trang chỉ số chạy thử.

### Nội dung lâm sàng

- [ ] Danh sách dấu hiệu cần chú ý (`backend/src/summary/red-flags.json`) đã được bác sĩ duyệt, đổi `reviewed` và `version`.
- [ ] Bộ câu hỏi trước khám đã được duyệt.
- [ ] Danh mục thuốc và ICD-10 của phòng khám đã thay danh mục mẫu (`backend/catalog/clinic-catalog.json`), hoặc chấp nhận dùng mẫu và ghi lại.
- [ ] Bác sĩ đã đọc thử 10 tóm tắt (điều kiện xong bước 17) và ghi nhận xét — xem mục 9.
- [ ] `npm run eval:summary` đạt với chế độ sẽ dùng thật.

### In đơn

- [ ] In đơn thuốc PDF trên **máy in thật** của phòng khám, **đúng khổ giấy** phòng khám dùng (web xuất A4 một trang): chữ đủ dấu, không bị cắt, mã nhận kết quả đọc được, chỗ bác sĩ ký tay và ô BHYT ghi tay đủ chỗ (R6, `doctor_web/README.md`).
- [ ] Phòng khám xác nhận mẫu đơn theo quy định hiện hành (R2).

### Dữ liệu cá nhân

- [ ] Hồ sơ đánh giá tác động đã được phòng khám/cố vấn pháp lý đối chiếu và hoàn tất theo yêu cầu của Luật Bảo vệ dữ liệu cá nhân và NĐ 356/2025/NĐ-CP.
- [ ] Lời văn màn chia sẻ đã bổ sung: AI ở nước ngoài (nếu dùng), thời gian lưu, cách yêu cầu xóa, liên hệ.
- [ ] Quy trình yêu cầu xóa thủ công (mục 8.5) đã được quản trị thử một lần.
- [ ] Nhân viên tiếp đón có tờ hướng dẫn ngắn: app làm gì, chia sẻ gì, rút lại thế nào, không dùng khi cấp cứu.

## 4. Lịch giai đoạn 1

| Ngày | Việc | Người |
| --- | --- | --- |
| Ngày −5 đến −1 | Hoàn tất mục 3; tập huấn bác sĩ 30 phút (hàng chờ, câu gốc, nút Đúng/Sai, kê đơn, gửi, sửa kết quả); tập huấn tiếp đón | Chủ dự án |
| Ngày 1 | Bắt đầu với 3–5 người bệnh; chủ dự án có mặt tại phòng khám; cuối ngày xem lỗi và nhật ký | Tất cả |
| Ngày 2–3 | Tăng dần đến toàn bộ người bệnh đồng ý của bác sĩ đó; trao đổi 10 phút cuối ngày | Bác sĩ, chủ dự án |
| Ngày 3 | Kiểm tra sao lưu của ngày 1–2 có đủ, thử khôi phục lại | Chủ dự án |
| Ngày 5 | Điểm giữa: xem 4 chỉ số tuần 1, sửa lỗi nhỏ (không đổi prompt/quy tắc giữa tuần nếu không cần thiết; nếu đổi thì ghi `prompt_version`) | Chủ dự án, bác sĩ |
| Ngày 6–9 | Chạy bình thường; quản trị xem nhật ký truy cập 1 lần | Tất cả |
| Ngày 10 | Bác sĩ điền phiếu góp ý (mục 9); xuất chỉ số | Bác sĩ, chủ dự án |
| Sau ngày 10 | Họp go/no-go (mục 7) | Người quyết định |

Mỗi ngày (chủ dự án, 10 phút): `/health` bình thường; có bản sao lưu mới; log không có lỗi lặp; số tóm tắt `failed` trong `audit_event` (`summary.generate`).

## 5. Lịch giai đoạn 2 (đề xuất)

- Tuần 1: thêm bác sĩ theo nhóm 2–3 người, quản trị tạo tài khoản, tập huấn như ngày −5.
- Tuần 2–4: chạy bình thường, xem chỉ số mỗi tuần, quản trị xem nhật ký truy cập mỗi tuần.
- Cuối tuần 4: tổng kết, quyết định dùng tiếp, sửa đổi hay dừng.

## 6. Thu thập 4 chỉ số

Nguồn chính: **trang chỉ số chạy thử của quản trị** (backend đang thêm ở bước 18). Bảng dưới ghi cách tính để kiểm lại với dữ liệu gốc; khi trang xong, đối chiếu định nghĩa của trang với bảng này.

| # | Chỉ số | Cách tính | Dữ liệu gốc |
| --- | --- | --- | --- |
| C1 | Số lượt có tóm tắt | Số lượt khám có ít nhất một dòng `visit_summary`; kèm mẫu số: số lượt khám trong kỳ (không tính `cancelled`) và số lượt có đồng ý `intake` | `visit_summary`, `appointment`, `consent` |
| C2 | Tỷ lệ bác sĩ bấm Đúng | Số tóm tắt có `feedback = up` / số tóm tắt được đánh giá (`up` + `down`). Báo kèm **tỷ lệ được đánh giá** = số được đánh giá / số lượt có tóm tắt, vì bác sĩ có thể bỏ qua nút | `visit_summary.feedback`, `audit_event` `summary.feedback` |
| C3 | Thời gian từ lúc khám xong đến lúc người bệnh nhận kết quả | Với mỗi lượt khám: từ lần gửi kết quả đầu tiên (`audit_event` `result.send`, version 1; ≈ lúc khám xong) đến lần đầu người bệnh mở kết quả (`result.view` hoặc `result.claim`, actor `patient`). Báo trung vị và phân vị 90; đếm riêng số lượt người bệnh chưa mở sau 24 giờ | `audit_event` |
| C4 | Số đơn phải sửa sau khi gửi | Số lượt khám có `result.amend` / số lượt có `result.send`. Ghi lý do sửa (`visit_result.amend_reason`) để phân loại: sai thuốc, sai liều, sai chẩn đoán, khác | `audit_event`, `visit_result` |

Ghi chú:

- C3 đo tới lúc người bệnh **mở** kết quả trong app, không phải lúc kết quả có sẵn (kết quả có sẵn ngay khi gửi). Người bệnh chỉ nhận đơn giấy thì không có thời điểm mở.
- Nếu đổi `CLINIC_AI_SUMMARY` hoặc prompt giữa kỳ, tách chỉ số theo `mode`/`prompt_version`.
- Bổ sung (không bắt buộc): số tóm tắt `failed`/`empty`; số cờ; số lần bác sĩ bấm Sai kèm ghi chú lý do (mục 9).
- Chỉ xuất số đếm ra khỏi máy chủ, không xuất lời người bệnh.

Truy vấn kiểm lại (chạy trên bản sao, SQL chuẩn):

```sql
-- C1
SELECT COUNT(DISTINCT s.appointment_id) FROM visit_summary s
JOIN appointment a ON a.id = s.appointment_id
WHERE a.starts_at >= :from AND a.starts_at < :to;
-- C2 (tóm tắt mới nhất của mỗi lượt có thể khác; đếm theo từng bản)
SELECT feedback, COUNT(*) FROM visit_summary
WHERE created_at >= :from AND created_at < :to GROUP BY feedback;
-- C4
SELECT COUNT(DISTINCT appointment_id) FROM audit_event
WHERE action = 'result.amend' AND at >= :from AND at < :to;
```

## 7. Tiêu chí mở rộng cho cả khoa (đề xuất)

Tất cả ngưỡng dưới đây là **đề xuất**, cần thống nhất trước ngày 1 để không chỉnh sau khi thấy số.

**Điều kiện bắt buộc (một điều không đạt là không mở rộng):**

| Tiêu chí | Ngưỡng đề xuất |
| --- | --- |
| Sự cố lộ dữ liệu | 0 |
| Đơn đã gửi sai thuốc/liều mà người bệnh đã dùng theo | 0 |
| Tóm tắt có thông tin **không có** trong lời người bệnh (bác sĩ phát hiện) | 0 trường hợp gây hại; mọi trường hợp đã được phân tích |
| Sót dấu hiệu cần chú ý mà người bệnh đã viết rõ | 0 |
| Sao lưu | Có đủ bản mỗi ngày; thử khôi phục thành công ít nhất 1 lần |
| Hồ sơ dữ liệu cá nhân | Hoàn tất; khoảng trống G1–G12 đã xử lý hoặc có quyết định chấp nhận |

**Chỉ số (đạt phần lớn thì mở rộng, không đạt thì họp xem nguyên nhân):**

| Chỉ số | Ngưỡng đề xuất | Ghi chú |
| --- | --- | --- |
| C1 | ≥ 20 lượt có tóm tắt trong 2 tuần | Ít hơn thì chưa đủ dữ liệu để kết luận, cân nhắc kéo dài 1 tuần |
| C2 | Tỷ lệ Đúng ≥ 80%, tỷ lệ được đánh giá ≥ 70% | |
| C3 | Trung vị ≤ 30 phút với người bệnh dùng app | |
| C4 | ≤ 10% đơn phải sửa; không lý do "sai do phần mềm" lặp lại | |
| Bác sĩ | Phiếu góp ý: muốn tiếp tục dùng; thời gian thêm mỗi lượt khám chấp nhận được | |

Kết quả có thể là: **mở rộng**; **kéo dài giai đoạn 1** (sửa rồi chạy thêm 1–2 tuần); **dừng**.

## 8. Xử lý sự cố

Mọi sự cố: ghi vào sổ sự cố (thời điểm, người phát hiện, mã lượt khám — không chép lời người bệnh, việc đã làm), báo chủ dự án và quản trị phòng khám trong ngày.

### 8.1 Tóm tắt sai

1. Bác sĩ bấm **Sai** trên tóm tắt, đọc câu gốc (web luôn hiện câu gốc cạnh tóm tắt), khám như thường. Tóm tắt chỉ để tham khảo.
2. Bác sĩ ghi một dòng vào sổ: sai kiểu gì (thêm ý, sai số, sai thuốc, thiếu ý quan trọng, cờ thừa/thiếu).
3. Chủ dự án xem `audit_event` `summary.generate` của lượt đó (mục bị bỏ, `promptVersion`), tái hiện bằng ca tương tự trong `eval/` (không dùng lời thật của người bệnh nếu chưa có đồng ý cho việc đó).
4. Nếu sai có thể gây hại (bịa triệu chứng, bỏ sót dấu hiệu nguy hiểm): chuyển `CLINIC_AI_SUMMARY=mock` hoặc `off` cho tới khi sửa và chạy lại eval.

### 8.2 Đơn đã gửi bị sai

1. Bác sĩ mở **Sửa kết quả**, ghi lý do, sửa và gửi lại. Bản cũ chuyển `amended`, app nhận bản mới; nhắc uống thuốc theo đơn mới (`med_course` được cập nhật, `CLINIC-API.md` bước 16).
2. **Gọi điện cho người bệnh** nếu sai thuốc hoặc liều — không dựa vào app để báo. Nếu người bệnh đã in/nhận đơn giấy, hướng dẫn hủy đơn cũ.
3. Ghi vào sổ; đếm vào C4.

### 8.3 Lộ hoặc nghi lộ dữ liệu

1. Phát hiện (ví dụ: tài khoản bị dùng lạ, truy cập bất thường trong nhật ký, máy bị mất): báo ngay chủ dự án và quản trị.
2. Ngăn chặn: khóa tài khoản liên quan; khởi động lại server để hủy mọi phiên bác sĩ (phiên chỉ trong bộ nhớ); thu hồi phiên người bệnh liên quan; nếu nghi lộ khóa thì đổi `OPENAI_API_KEY`, `PATIENT_OTP_PEPPER`.
3. Đánh giá: dùng `audit_event` xác định ai đã xem hồ sơ nào, khi nào, từ IP nào.
4. Thông báo: thời hạn và nơi nhận thông báo vi phạm theo Luật Bảo vệ dữ liệu cá nhân và NĐ 356/2025/NĐ-CP — **cần đối chiếu điều khoản**, phòng khám quyết định; thông báo người bệnh bị ảnh hưởng.
5. Dừng chạy thử cho tới khi khắc phục.

### 8.4 Máy chủ ngừng hoạt động

1. Bác sĩ khám và kê đơn như trước (HIS/giấy). Không chờ hệ thống.
2. Chủ dự án khôi phục: khởi động lại; nếu CSDL hỏng thì khôi phục bản sao lưu gần nhất. Dữ liệu sau bản sao lưu có thể mất: app giữ dữ liệu chưa gửi trong hàng chờ và gửi lại; kết quả bác sĩ đã gửi sau thời điểm sao lưu phải nhập lại.
3. Khi server khởi động lại: bác sĩ phải đăng nhập lại; tóm tắt đang chờ bị bỏ, sẽ chạy lại khi người bệnh gửi câu trả lời tiếp (`worker.js`).
4. Ghi thời gian ngừng vào sổ.

### 8.5 Người bệnh muốn rút lại hoặc xóa dữ liệu

- Rút lại: người bệnh làm trên app ("Xem, đổi hoặc rút lại"); bác sĩ không còn thấy từ lần tải sau.
- Xóa: hệ thống **chưa có** chức năng xóa. Quy trình tạm: người bệnh báo phòng khám → quản trị ghi yêu cầu → chủ dự án xóa các dòng `intake_answer`, `self_medication`, `dose_event`, `visit_summary` liên quan (theo quyết định của phòng khám về dữ liệu đã dùng để khám) và ghi lại việc xóa → báo người bệnh. Thời hạn trả lời: cần đối chiếu điều khoản.

## 9. Phiếu góp ý của bác sĩ

Điền cuối giai đoạn 1 (và cuối giai đoạn 2 với mỗi bác sĩ). Phần A làm trước ngày 1 (điều kiện xong bước 17).

**A. Đọc thử 10 tóm tắt**

Chủ dự án chuẩn bị 10 lượt (từ bộ mẫu `eval/summary-cases.json` hoặc người bệnh đồng ý), đủ loại: tái khám bệnh mạn, bệnh cấp, người cao tuổi, tự dùng thuốc, gõ không dấu, có dấu hiệu nguy hiểm, có câu phủ định. Với mỗi tóm tắt:

| # | Đúng ý người bệnh? (Có/Một phần/Không) | Có ý bịa thêm? | Thiếu ý quan trọng? | Cờ đúng/thừa/thiếu? | Đọc nhanh hơn câu gốc? | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | | | | | | |
| … | | | | | | |
| 10 | | | | | | |

**B. Dùng trong khám (thang 1–5, kèm một câu giải thích)**

1. Tóm tắt giúp tôi chuẩn bị trước khi người bệnh vào.
2. Tôi tin tóm tắt đủ để không cần đọc câu gốc. (Mong đợi: không — câu gốc vẫn cần.)
3. Cờ dấu hiệu cần chú ý có ích / gây nhiễu.
4. Tuân thủ thuốc 30 ngày có ích cho quyết định điều trị.
5. Kê đơn trên web nhanh như cách hiện tại.
6. Đơn in ra đúng mẫu, đọc được.
7. Thời gian thêm cho mỗi lượt khám (phút): ___

**C. Câu hỏi mở**

- Lần nào tóm tắt sai mà có thể gây hại? Mô tả (không ghi tên người bệnh).
- Điều gì làm chậm anh/chị nhất?
- Nên bỏ, thêm hay đổi gì trước khi mở cho cả khoa?
- Anh/chị có muốn tiếp tục dùng không? Vì sao?
