# MedicApp — Khung app Flutter Android

**Bước 4:** Đã thêm chuyển động nhẹ, loading skeleton, giảm chuyển động và cải thiện cỡ chữ lớn cho luồng đặt lịch. Xem [chi tiết UI/UX](UI-UX.md).

App `medic_app` hiện mở **Trang chủ**, có shell bốn tab, nút Đặt lịch ở giữa và trạng thái hồ sơ/thông báo bằng Riverpod. Đã có luồng đặt lịch cơ bản và thanh toán giả lập, xem [bước 3](BOOKING.md). Chưa có backend hoặc Smart Scheduling. Xem [khung điều hướng bước 2](NAVIGATION.md) và [nền giao diện bước 1](DESIGN-SYSTEM.md).

- Nền tảng: Android.
- Flutter 3.47.7 stable, Dart 3.13.5.
- Java: Eclipse Temurin 21.0.12.1+1.
- Application ID tạm: `com.example.medic_app`; cần đổi trước khi phát hành.
- Entry point cục bộ: `lib/main.dart`.
- Tests: giao diện, điều hướng, trạng thái và luồng đặt lịch trong `test/`; ảnh chuẩn trong `test/goldens/`. Bộ kiểm tra hiện gồm 52 test.

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
