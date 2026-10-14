# Kiểm tra môi trường — 2026-10-14

- SHA256 của Flutter, Java, Android command-line tools và gh: khớp manifest chính thức.
- Flutter 3.47.7 stable; Dart 3.13.5.
- Eclipse Temurin JDK 21.0.12.1+1.
- GitHub CLI 2.102.0 chạy được; người dùng sẽ tự đăng nhập.
- Android SDK platform 36, build-tools 36.0.0, platform-tools và NDK 28.2.13676358 đã cài trong dự án; license đã chấp nhận.
- `flutter doctor -v`: Flutter, Windows host, Android toolchain và network đều hợp lệ. Cảnh báo duy nhất còn lại: chưa có thiết bị Android kết nối.
- Script PowerShell: không có lỗi cú pháp; kích hoạt lặp lại và khôi phục biến môi trường đã kiểm tra.
- `uninstall.ps1 -WhatIf`: chạy thành công; chưa chạy thao tác gỡ thật.
- Flutter Android starter đã tạo tại `05-prototype/flutter_app`.
- `flutter analyze`: No issues found.
- `flutter test`: All tests passed (1 test mẫu từ Flutter).
- `flutter build apk --debug`: Thành công; APK tại `05-prototype/flutter_app/build/app/outputs/flutter-apk/app-debug.apk` (150.495.964 byte).
- Debug keystore được tạo tại `.devcache/android/debug.keystore`, không nằm trong source và không được commit.
- `gh auth status`: Chưa đăng nhập vào GitHub host nào; người dùng tự thực hiện bước đăng nhập.
- Gradle daemon của lần build đầu đã được dừng để giải phóng tài nguyên.

Chưa chạy thử trên thiết bị Android vì chưa có điện thoại/emulator kết nối.
