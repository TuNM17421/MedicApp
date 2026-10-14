# MedicApp — Flutter Android starter

App `medic_app` được khởi tạo bằng template chính thức của Flutter. Hiện là màn hình đếm mẫu để kiểm tra công cụ; chưa phải prototype MyVinmec, chưa có dữ liệu bệnh nhân hay kết nối backend.

- Nền tảng: Android.
- Flutter 3.47.7 stable, Dart 3.13.5.
- Java: Eclipse Temurin 21.0.12.1+1.
- Application ID tạm: `com.example.medic_app`; cần đổi trước khi phát hành.
- Entry point cục bộ: `lib/main.dart`.
- Test mẫu cục bộ: `test/widget_test.dart`.

Bản Git hiện tại chỉ bàn giao tài liệu; source Flutter và script môi trường chưa được đẩy. Các lệnh dưới đây dùng trên máy đã thiết lập môi trường, chưa phải hướng dẫn clone bản tài liệu và build ngay.

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

Codex thực hiện thiết lập và chạy công cụ tạo project. Source và test ban đầu được sinh từ template Flutter, chưa có giao diện nghiệp vụ do AI thiết kế. Chi tiết yêu cầu được ghi trong [prompt log](../prompts/README.md).
