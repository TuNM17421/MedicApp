# MedicApp — Khung app Flutter Android

**Bước 4:** Đã thêm chuyển động nhẹ, loading skeleton, giảm chuyển động và cải thiện cỡ chữ lớn cho luồng đặt lịch. Xem [chi tiết UI/UX](UI-UX.md).

**Bước 9:** Có icon và màn mở app riêng, hình minh họa, lịch tháng ở trang Lịch hẹn và chuyển động nhẹ (tắt khi giảm chuyển động). Xem [bước 9](LAM-DEP-UI.md).

**Bước 10:** Hồ sơ gia đình được lưu trên máy (mã hóa AES-256-GCM, khóa giữ trong Android Keystore) sau khi chủ tài khoản đồng ý ở màn hình "Lưu dữ liệu sức khỏe". Không đồng ý thì app chạy như cũ, dữ liệu mất khi đóng app. Rút lại đồng ý ở Tài khoản sẽ xóa dữ liệu khỏi máy. Xem [bước 10](LUU-TRU-DU-LIEU.md).

**Bước 11:** Kết quả khám và đơn thuốc theo mẫu Bộ Y tế (Thông tư 18/2018/TT-BYT), do một web bác sĩ giả lập gửi về cho từng lượt khám. Xem dạng dễ đọc hoặc dạng giống tờ đơn giấy. Lịch hẹn và kết quả giờ được lưu theo từng tài khoản. Xem [bước 11](DON-THUOC.md).

**Bước 12:** Nhắc uống thuốc theo đơn: thông báo đúng giờ có nút "Đã uống" và "Nhắc lại sau 10 phút", nhắc lại sau 30 phút nếu chưa ghi, báo sắp hết thuốc. Màn "Thuốc hôm nay" ghi đã uống hoặc bỏ liều kèm lý do, xem lịch sử 4 tuần cho từng người. Xem [bước 12](NHAC-THUOC.md).

**Bước 8:** App đặt thông báo nhắc khám trên điện thoại, chọn giờ theo thời gian phải kiêng và nội dung theo tuổi, giới của người khám. Xem [bước 8](THONG-BAO-NHAC-KHAM.md).

**Bước 7:** Có lưu ý cá nhân hóa trước khi khám cho 5 bệnh, đọc từ hồ sơ và lịch hẹn. Xem [bước 7](LUU-Y-TRUOC-KHAM.md).

**Bước 6:** Có đăng ký, đăng nhập (giả lập trong máy) và tạo hồ sơ nhanh bằng quét mã QR trên CCCD. Xem [bước 6](AUTH-CCCD.md).

App `medic_app` mở màn **Chào mừng** khi chưa đăng nhập, sau đó vào **Trang chủ**, có shell bốn tab, nút Đặt lịch ở giữa và trạng thái hồ sơ/thông báo bằng Riverpod. Đã có luồng đặt lịch cơ bản và thanh toán giả lập, xem [bước 3](BOOKING.md). Có Đặt lịch thông minh bằng giọng nói hoặc nhập tay, cần chạy [backend local](../backend/README.md); xem [bước 5](SMART-SCHEDULING.md). Xem [khung điều hướng bước 2](NAVIGATION.md) và [nền giao diện bước 1](DESIGN-SYSTEM.md).

- Nền tảng: Android.
- Flutter 3.47.7 stable, Dart 3.13.5.
- Java: Eclipse Temurin 21.0.12.1+1.
- Application ID tạm: `com.example.medic_app`; cần đổi trước khi phát hành.
- Entry point cục bộ: `lib/main.dart`.
- Tests: giao diện, điều hướng, trạng thái và luồng đặt lịch trong `test/`; ảnh chuẩn trong `test/goldens/`. Bộ kiểm tra hiện gồm 138 test (129 pass, 1 bỏ qua); 8 test ảnh chuẩn cần cập nhật trên Windows (xem bước 5).

Source Flutter, font, tests và script môi trường đã được đưa vào bản bàn giao này. Trên máy Windows mới cần Git và chạy `scripts/setup.ps1` từ gốc repo để tải bộ công cụ trước khi kích hoạt; SDK/cache không nằm trong Git.

## Chạy từ gốc repository

```powershell
. .\scripts\activate.ps1
Set-Location .\05-prototype\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run
```

APK debug được tạo tại `build/app/outputs/flutter-apk/app-debug.apk` và bị loại khỏi Git. Cần kết nối điện thoại Android đã bật USB debugging để `flutter run`; chưa cài emulator. APK debug chỉ dành cho thử nghiệm.

## Lệnh đã dùng để khởi tạo

```powershell
flutter create --platforms=android --project-name medic_app --org com.example --description "Flutter Android prototype for the MedicApp research project." .\05-prototype\flutter_app
```

Lệnh trên chạy từ gốc repo và chỉ dùng khi khởi tạo. Xem [hướng dẫn môi trường](../../scripts/README.md) để cài lại, đăng nhập gh hoặc gỡ SDK/cache.

## AI disclosure

Codex thực hiện thiết lập project và triển khai bước 1–4 từ prototype đã duyệt bố cục. Code, dữ liệu giả định và test do AI viết; font Be Vietnam Pro và icon Lucide từ các nguồn được ghi trong tài liệu nền giao diện. Đã cài/mở app trên OPPO A77s; chủ dự án báo đã thử xong luồng đặt lịch, chưa có log chi tiết để suy ra chỉ số UX. Không thu tiền thật. Chi tiết yêu cầu được ghi trong [prompt log](../prompts/README.md).
