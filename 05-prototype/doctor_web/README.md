# Web bác sĩ (bước 14–18)

Web cho bác sĩ phòng khám đối tác, viết bằng Flutter Web theo bản bấm thử đã duyệt (`prototype/web-bac-si`). Bước này có: đăng nhập, **Hàng chờ**, **Hồ sơ** một lượt khám (cột người bệnh và 3 tab), tab **Tóm tắt trước khám** có câu gốc và tuân thủ thuốc 30 ngày, tab **Lịch sử khám**.

Bước 15 thêm tab **Kết quả & đơn thuốc**: ghi chẩn đoán (tìm ICD-10, thêm nhanh bệnh đang theo dõi), kê đơn (chọn thuốc từ danh mục, liều theo buổi sáng/trưa/chiều/tối, trước/sau ăn, số ngày, số lượng tự tính, dùng lại đơn lần trước), lời dặn và hẹn tái khám, ghi chú nội bộ. Mọi thay đổi tự lưu nháp. **Xem đơn theo mẫu** hiện đơn đúng mẫu Thông tư 18/2018/TT-BYT; **In đơn thuốc** và **Tải PDF** cho bản A4 giống hệt. **Ký và gửi kết quả** khóa kết quả và tạo **mã nhận kết quả** (in cuối đơn, hiện trên web); người bệnh nhập mã này trong app để nhận kết quả và lịch uống thuốc. **Sửa kết quả** mở bản mới có ghi lý do, bản đã gửi giữ nguyên.

Bước 18 thêm vai trò **quản trị** phòng khám và vài phần vận hành:

- **Tài khoản** (quản trị): thêm bác sĩ hoặc quản trị, mật khẩu tạm hiện một lần (có nút chép), khóa / mở lại, đặt lại mật khẩu. Trạng thái: Đang dùng, Chờ đổi mật khẩu, Tạm khóa do nhập sai, Đã khóa.
- **Số liệu chạy thử** (quản trị): lượt khám có tóm tắt, tỷ lệ bác sĩ bấm "Đúng", thời gian từ lúc gửi kết quả tới lúc người bệnh nhận (trung vị), số đơn phải sửa sau khi gửi; bảng theo ngày; chọn 7, 30 hoặc 90 ngày. Cách tính ở [CLINIC-API.md](../backend/CLINIC-API.md#số-liệu-chạy-thử).
- **Nhật ký truy cập**: bác sĩ bấm "Nhật ký truy cập" ở cột người bệnh của hồ sơ; quản trị tra theo mã người bệnh ở trang Nhật ký. Ai, làm gì, lúc nào, lượt khám nào; "Tải thêm" để xem trang sau.
- **Đổi mật khẩu** trong menu tài khoản. Đăng nhập bằng mật khẩu tạm thì chỉ có màn "Đặt mật khẩu mới" cho tới khi đổi xong (tối thiểu 10 ký tự, không trùng email).
- Router chặn theo vai trò: quản trị luôn về trang quản trị (không xem hàng chờ, hồ sơ), bác sĩ không vào `/admin/*`; server cũng chặn (`403 forbidden`). Khi mở trang, web chờ server trả phiên (`GET /v1/staff/session`) rồi mới dựng trang, nên không gọi dữ liệu không được xem.
- Dấu ✓ của dải tuân thủ lấy từ `assets/fonts/dejavu/DejaVuSans-Check.ttf` (DejaVu Sans chỉ giữ một ký tự, giấy phép kèm theo) vì Be Vietnam Pro không có. Trước đây Flutter tự tải font Noto từ `fonts.gstatic.com` cho ký tự này; CSP của bước 18 (`connect-src 'self'`) chặn mọi tải ngoài.

## Chạy thử

```powershell
# 1. Build web (từ 05-prototype/doctor_web)
flutter pub get
flutter build web --base-href /doctor/ --no-web-resources-cdn

# 2. Backend (từ 05-prototype/backend): dữ liệu mẫu rồi chạy
npm ci
$env:SEED_CLAIM_CODE="K7MQ-4XR2-9D"   # tùy chọn: mã nhận cố định cho kết quả mẫu của ông Minh
npm run seed
npm start
```

Mở `http://localhost:8080/doctor/`, đăng nhập `bs.ha@anbinh.test` / `medicapp-demo` (bác sĩ) hoặc `quantri@anbinh.test` / `medicapp-demo` (quản trị). Dữ liệu mẫu là 6 người bệnh của bản bấm thử, lịch vào ngày chạy seed. Xem [backend README](../backend/README.md#web-bác-sĩ) và [hợp đồng API](../backend/CLINIC-API.md).

`--no-web-resources-cdn` gói CanvasKit vào bản build thay vì tải từ CDN của Google, nên web chạy được ở mạng phòng khám chặn bên ngoài và không lộ địa chỉ truy cập cho bên thứ ba.

Khi sửa giao diện, có thể chạy `flutter run -d web-server --web-port 5000 --dart-define=API_BASE_URL=http://localhost:8080` và đặt `DOCTOR_WEB_DEV_ORIGIN=http://localhost:5000` trong `backend/.env`. Dùng `localhost` ở cả hai, không trộn với `127.0.0.1`.

## Cấu trúc

| File | Nội dung |
| --- | --- |
| `lib/app/theme.dart` | Màu sáng/tối theo `tokens.css` của bản bấm thử (màu tuân thủ đã qua kiểm tra mù màu), cỡ chữ, nút. |
| `lib/app/router.dart`, `shell.dart` | go_router, chuyển về đăng nhập khi chưa có hoặc hết phiên; thanh trên và thanh điều hướng. |
| `lib/data/` | `ClinicApi` (gửi kèm cookie phiên), model theo `CLINIC-API.md`, provider Riverpod. Giờ đọc theo giờ phòng khám (`+07:00`), không đổi sang múi giờ máy xem. |
| `lib/features/worklist/` | Hàng chờ: lọc, tìm tên hoặc mã, bảng (màn rộng) hoặc thẻ (màn hẹp), tuân thủ 30 ngày. |
| `lib/features/chart/` | Cột người bệnh, tab Tóm tắt (câu gốc, cảnh báo, tuân thủ, đánh giá tóm tắt), Lịch sử, Kết quả. |
| `lib/features/admin/` | Trang quản trị: Tài khoản, Số liệu chạy thử, Nhật ký truy cập (bước 18). |
| `lib/features/login/password_page.dart`, `lib/features/chart/access_log.dart` | Đổi mật khẩu (bắt buộc khi có mật khẩu tạm); danh sách và hộp thoại nhật ký truy cập. |
| `lib/features/result/` | Kê đơn (`rx_editor.dart`), mẫu đơn dùng chung cho màn hình và PDF (`rx_sheet.dart`, `rx_pdf.dart`), hộp thoại xem mẫu, gửi, sửa. |
| `lib/core/charts/` | Dải 30 ngày (mỗi ô có ✓ ½ ×, rê chuột xem chi tiết) và biểu đồ lý do bỏ liều; có chế độ xem dạng bảng. |

Đơn và PDF dùng font Tinos (giấy phép OFL, cùng khổ chữ với Times New Roman của mẫu Bộ Y tế, đủ dấu tiếng Việt) trong `assets/fonts/tinos/`.

Tỷ lệ tuân thủ do `medic_core` tính từ nhật ký thô backend trả về, cùng quy tắc với màn Thuốc hôm nay của app. Backend không tính lại.

## Kiểm tra

- `flutter analyze`: không có lỗi.
- `flutter test`: 20 test. Bước 18 (`test/admin_test.dart`): quản trị vào Tài khoản và không gọi hàng chờ, tạo tài khoản và mật khẩu tạm, khóa và đặt lại mật khẩu, số liệu chạy thử, tra nhật ký theo mã, bác sĩ bị chặn khỏi trang quản trị, bắt đổi mật khẩu tạm, nhật ký truy cập trên hồ sơ và tải thêm. Các test trước: Bước 14: đăng nhập và sai mật khẩu, hàng chờ và tỷ lệ 75% của bà Lan, câu gốc, 18/30 và 27/30 liều, xem dạng bảng, người không chia sẻ, lịch sử, màn 390 px, hết phiên). Bước 15 (`test/result_test.dart`): dùng lại đơn cũ, tự lưu nháp, ký gửi và hiện mã, mở bản sửa; chọn thuốc, liều 1 + 1,5 viên × 7 ngày ra 18 viên; PDF một trang A4. Test nạp font Be Vietnam Pro thật để bắt lỗi tràn chữ.
- Đã chạy bản build với backend thật trên Chromium ở 1440, 1024 và 390 px, sáng và tối: không có lỗi console. Bước 15: kê đơn, xem mẫu và tải PDF từ trình duyệt; PDF một trang, đủ dấu.
- Bước 18 đã chạy bản build với backend thật trên Chromium (Playwright) ở 1440 px sáng và 390 px tối: đăng nhập bác sĩ, hồ sơ, nhật ký truy cập, bác sĩ mở `#/admin/accounts` bị đưa về hàng chờ, quản trị tạo tài khoản, số liệu, tra nhật ký, tài khoản mới đăng nhập bằng mật khẩu tạm bị bắt đổi rồi vào hàng chờ. Có CSP: không lỗi console, không vi phạm CSP, không yêu cầu nào ra ngoài origin.

## Giới hạn

- Web dùng hash URL (`/doctor/#/visit/...`); đường dẫn dạng `/doctor/visit/...` mở về hàng chờ.
- Ký tự không có trong font kèm theo (chữ Hán, emoji trong câu trả lời của người bệnh) hiện ô trống: CSP không cho tải font từ Google.
- Tóm tắt trong dữ liệu mẫu viết sẵn (`mode: mock`); tóm tắt bằng AI ở bước 17.
- Danh mục thuốc và ICD-10 là danh mục mẫu (`backend/catalog/clinic-catalog.json`), chưa phải danh mục của phòng khám.
- Chưa có chữ ký số: đơn in ra bác sĩ ký tay. Mã thẻ BHYT trên web đã che nên ô BHYT trên đơn để trống cho ghi tay.
- Người bệnh chưa có tài khoản trên máy chủ nên nhận kết quả bằng mã; bước 16 thay bằng liên kết tài khoản.
- Người bệnh chưa gửi dữ liệu thật từ app; đồng ý chia sẻ và gửi nhật ký thuốc ở bước 16.
