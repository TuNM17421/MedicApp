# Bước 14: Web bác sĩ, phần xem

Web cho bác sĩ phòng khám đối tác, viết bằng Flutter Web theo bản bấm thử đã duyệt (`prototype/web-bac-si`). Bước này có: đăng nhập, **Hàng chờ**, **Hồ sơ** một lượt khám (cột người bệnh và 3 tab), tab **Tóm tắt trước khám** có câu gốc và tuân thủ thuốc 30 ngày, tab **Lịch sử khám**. Kê đơn, in đơn và gửi kết quả về app làm ở bước 15; tab **Kết quả & đơn thuốc** hiện báo điều đó.

## Chạy thử

```powershell
# 1. Build web (từ 05-prototype/doctor_web)
flutter pub get
flutter build web --base-href /doctor/ --no-web-resources-cdn

# 2. Backend (từ 05-prototype/backend): dữ liệu mẫu rồi chạy
npm ci
npm run seed
npm start
```

Mở `http://localhost:8080/doctor/`, đăng nhập `bs.ha@anbinh.test` / `medicapp-demo`. Dữ liệu mẫu là 6 người bệnh của bản bấm thử, lịch vào ngày chạy seed. Xem [backend README](../backend/README.md#web-bác-sĩ) và [hợp đồng API](../backend/CLINIC-API.md).

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
| `lib/core/charts/` | Dải 30 ngày (mỗi ô có ✓ ½ ×, rê chuột xem chi tiết) và biểu đồ lý do bỏ liều; có chế độ xem dạng bảng. |

Tỷ lệ tuân thủ do `medic_core` tính từ nhật ký thô backend trả về, cùng quy tắc với màn Thuốc hôm nay của app. Backend không tính lại.

## Kiểm tra

- `flutter analyze`: không có lỗi.
- `flutter test`: 7 test (đăng nhập và sai mật khẩu, hàng chờ và tỷ lệ 75% của bà Lan, câu gốc, 18/30 và 27/30 liều, xem dạng bảng, người không chia sẻ, lịch sử, màn 390 px, hết phiên). Test nạp font Be Vietnam Pro thật để bắt lỗi tràn chữ.
- Đã chạy bản build với backend thật trên Chromium ở 1440, 1024 và 390 px, sáng và tối: không có lỗi console.

## Giới hạn

- Mới có một vai trò bác sĩ; tài khoản do seed tạo. Quản lý tài khoản, HTTPS và sao lưu ở bước 18.
- Tóm tắt trong dữ liệu mẫu viết sẵn (`mode: mock`); tóm tắt bằng AI ở bước 17.
- Người bệnh chưa gửi dữ liệu thật từ app; đồng ý chia sẻ và gửi nhật ký thuốc ở bước 16.
