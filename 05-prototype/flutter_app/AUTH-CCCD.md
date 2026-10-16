# Đăng ký, đăng nhập và tạo hồ sơ bằng QR CCCD — bước 6

Ngày 2026-10-15. Xây trên nhánh Đặt lịch thông minh (bước 5). Đăng nhập là **giả lập trong máy**: không có server, không ghi xuống ổ đĩa, tài khoản mới mất khi tắt app. Giữ đúng quy tắc của dự án là không kết nối dịch vụ thật.

## Trải nghiệm

- **Chào mừng:** khi chưa đăng nhập, app mở màn Chào mừng với hai nút lớn “Tạo tài khoản mới” và “Tôi đã có tài khoản”.
- **Tạo tài khoản (bước 1/2):** số điện thoại (10 số, chấp nhận dấu cách, dấu chấm, +84), mật khẩu ít nhất 6 ký tự, nhập lại mật khẩu. Ô mật khẩu có nút chữ “Hiện/Ẩn” thay vì chỉ biểu tượng con mắt. Lỗi viết bằng câu đầy đủ ngay dưới ô.
- **Hồ sơ của bạn (bước 2/2):** tài khoản mới phải tạo hồ sơ bản thân trước khi vào app. Hai cách: “Quét mã QR trên CCCD” (nhấn mạnh là nhanh nhất, có hình thẻ chỉ vị trí mã QR) hoặc “Tự nhập thông tin”. Có “Dùng số điện thoại khác” để quay lại.
- **Quét QR:** camera có khung vuông, tự đọc khi thấy mã, có nút Bật đèn. Nếu camera không mở được hoặc không có quyền, màn hình nói rõ và vẫn còn “Chọn ảnh có mã QR” (đọc mã từ ảnh trong máy) và “Tự nhập thông tin”. Quét nhầm mã khác (link, mã sản phẩm) thì báo đây không phải mã CCCD và giữ nguyên màn quét.
- **Kiểm tra thông tin:** họ tên, ngày sinh, giới tính và địa chỉ được điền sẵn, người dùng sửa được rồi bấm “Lưu hồ sơ”. Số CCCD chỉ hiện dạng che `079••••••234`.
- **Người thân:** tab Hồ sơ có “Thêm hồ sơ người thân”, cùng hai cách trên, thêm câu hỏi “Người này là gì của bạn?”.
- **Tài khoản:** hiện số điện thoại đăng nhập và nút Đăng xuất (có hỏi lại).
- **Tài khoản mẫu:** `0912 345 678`, mật khẩu `123456`, có sẵn gia đình mẫu như các bước trước. Màn Đăng nhập có nút “Điền tài khoản mẫu”.

## Định dạng QR trên CCCD

Mã QR ở mặt trước thẻ CCCD gắn chip là chuỗi phân tách bằng `|`:

```
số CCCD (12 số)|số CMND cũ|họ tên|ngày sinh ddMMyyyy|giới tính|nơi thường trú|ngày cấp ddMMyyyy
```

Thẻ mới hơn có thêm vài trường phía sau, thường để trống; parser bỏ qua. `parseCccdQr` từ chối mã không đúng dạng (`notCccd`) và mã thiếu họ tên hoặc ngày sinh hợp lệ (`unreadable`).

Ảnh QR chủ dự án gửi đã được giải mã trong môi trường làm việc để đối chiếu: đọc được đủ số CCCD, họ tên, ngày sinh, giới tính, địa chỉ và ngày cấp theo đúng định dạng trên. Ảnh và dữ liệu giải mã **không** đưa vào repo; test dùng dữ liệu giả cùng định dạng.

## Mã nguồn

| Tệp | Nội dung |
| --- | --- |
| `lib/features/auth/auth_controller.dart` | Kho tài khoản giả lập, `authSessionProvider`, kiểm tra số điện thoại/mật khẩu |
| `lib/features/auth/auth_pages.dart` | Chào mừng, Đăng nhập, Tạo tài khoản, `FormPageScaffold` |
| `lib/features/profiles/cccd_qr.dart` | `parseCccdQr`, `CccdData`, che số CCCD |
| `lib/features/profiles/cccd_scanner.dart` | `CccdScanner`: camera (`mobile_scanner`) và chọn ảnh (`image_picker`); thay bằng bản giả trong test |
| `lib/features/profiles/add_profile_pages.dart` | Chọn cách tạo hồ sơ, màn quét, màn kiểm tra/nhập thông tin |
| `lib/app/router/app_router.dart` | `authRedirect`: chưa đăng nhập chỉ vào được màn đăng nhập; tài khoản mới chưa có hồ sơ chỉ vào được màn tạo hồ sơ |

Hồ sơ gắn với tài khoản: `profileCatalogProvider` đọc hồ sơ của tài khoản đang đăng nhập. `PreviewProfile` có thêm `gender`, `idNumber`, `address` (không bắt buộc).

Package mới: `mobile_scanner` (nhận diện QR bằng ML Kit ngay trên máy, ảnh camera không gửi đi), `image_picker`. Quyền camera do `mobile_scanner` khai báo và chỉ được hỏi khi mở màn quét.

## Kiểm tra

- `test/auth/cccd_qr_test.dart`: đọc đủ trường, thẻ có trường thừa và số CMND cũ, từ chối mã không phải CCCD, từ chối ngày sinh sai.
- `test/auth/auth_flow_test.dart`: quy tắc chuyển hướng; kiểm tra số điện thoại và mật khẩu; tạo tài khoản → quét CCCD (có quét nhầm) → kiểm tra → lưu → Trang chủ chào đúng tên → đăng xuất → đăng nhập lại; tài khoản mẫu và sai mật khẩu; thêm người thân từ ảnh (có ảnh không có mã); nhập tay với lỗi bắt buộc và ngày sai; năm màn mới ở 360 px chữ 200% không tràn.

Kết quả 2026-10-15 trên Linux (Flutter 3.47.7): `flutter analyze` sạch; 85 test pass (thêm 17), 8 test ảnh chuẩn vẫn lệch như ghi chú ở bước 5 vì render font khác Windows. Test “app opens…” trong `widget_test.dart` nay kiểm tra màn Chào mừng.

**Chưa kiểm chứng:** chưa build APK và chưa quét bằng camera thật (môi trường không có Android SDK hay camera); màn quét trong ảnh xem trước dùng khung giả thay camera. Cần thử trên OPPO A77s: quét thẻ thật trong phòng sáng/tối, chọn ảnh QR đã gửi, từ chối quyền camera. Chưa có quên mật khẩu, xác thực OTP hay lưu đăng nhập sau khi tắt app; các phần này cần backend thật.

Code, test và tài liệu của bước này do AI tạo theo yêu cầu chủ dự án; không có log thử người dùng thật.
