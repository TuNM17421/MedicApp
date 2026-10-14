# Môi trường Flutter Android riêng cho MedicApp

**Lưu ý bản bàn giao:** Commit tài liệu hiện tại chỉ chứa README, kết quả kiểm tra và manifest. Các file `.ps1` đã có trên máy phát triển nhưng chưa được đẩy; cần bàn giao script trước khi có thể chạy các lệnh này trên máy mới.

Bộ công cụ Windows x64 portable nằm trong `.devtools/`; SDK và cache không được commit. Không sửa PATH hoặc biến môi trường ở cấp User/Machine, không cài Android Studio, emulator hay driver USB. Git hiện có được tái sử dụng; trên máy khác cần Git trong PATH.

Phiên bản và SHA256 gói tải về được khóa trong [toolchain.json](toolchain.json). Bộ hiện tại gồm Flutter 3.47.7, Dart 3.13.5, Temurin Java 21.0.12.1+1, Android SDK 36 / build-tools 36.0.0 / NDK 28.2.13676358 và gh 2.102.0. Android SDK cài bằng `sdkmanager`; `platform-tools` dùng bản máy chủ cung cấp tại thời điểm cài. Các gói bổ sung mà Gradle yêu cầu sẽ được tải trong lần build đầu.

Xem [kết quả kiểm tra](verification.md): analyze, test và build APK debug đều thành công. Chưa chạy app trên thiết bị.

## Cài lại trên máy khác

Mở PowerShell tại gốc repo:

```powershell
.\scripts\setup.ps1
```

Script hiển thị license Android để người dùng đọc và chấp nhận. Nếu đã đọc và đồng ý có thể chạy `setup.ps1 -AcceptAndroidLicenses`.

## Kích hoạt và sử dụng

```powershell
. .\scripts\activate.ps1
flutter doctor -v
gh --version
Set-Location .\05-prototype\flutter_app
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run
```

Dot-source (dấu chấm và dấu cách đầu dòng) giúp PATH có hiệu lực trong terminal hiện tại. Mỗi terminal mới cần kích hoạt lại. Nếu Execution Policy chặn, có thể mở một phiên `powershell -NoProfile -ExecutionPolicy Bypass`; không cần đổi policy toàn máy.

`USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, Pub, Gradle, Android và cấu hình gh được trỏ vào `.devcache/` trong phiên đã kích hoạt để giảm file sót lại. Điều này cũng ảnh hưởng cách các công cụ khác trong phiên tìm cấu hình người dùng. Dùng terminal này riêng cho dự án và chạy `. .\scripts\deactivate.ps1` ở gốc repo, hoặc đóng terminal khi xong.

## Đăng nhập GitHub

Tại gốc repo, trong terminal của bạn:

```powershell
. .\scripts\activate.ps1
gh auth login --hostname github.com --git-protocol https --web
gh auth status
```

Tự hoàn tất xác thực trên trình duyệt; không gửi token vào chat hoặc lưu token trong source. Cấu hình gh riêng nằm ở `.devcache/gh`; thông tin xác thực có thể được lưu trong Windows Credential Manager. Luôn kích hoạt môi trường trước khi dùng gh để sử dụng cùng cấu hình.

Chưa cấu hình remote hoặc đẩy code; thực hiện sau khi đăng nhập và xác định repository đích. Vì repo này chứa toàn bộ bài nộp, Git repository sẽ nằm ở gốc MedicApp, không nằm riêng trong app Flutter.

## Chạy trên điện thoại Android

Bật Developer options và USB debugging trên điện thoại; kết nối USB và chấp nhận thông báo cho phép máy tính. Kiểm tra `adb devices` / `flutter devices`, sau đó `flutter run`. Một số thiết bị Windows cần driver riêng của hãng; driver đó không nằm trong bộ portable này.

## Gỡ môi trường

Đóng app/debug session. Nếu đã đăng nhập gh, chạy trong môi trường đã kích hoạt:

```powershell
gh auth logout --hostname github.com
```

Sau đó, tại gốc repo:

```powershell
.\scripts\uninstall.ps1 -WhatIf
.\scripts\uninstall.ps1
```

Script dừng ADB/Gradle rồi xóa `.devtools/`, `.devcache/` và các file build/cache được liệt kê cố định. Source, tài liệu nghiên cứu và `pubspec.lock` được giữ lại. Không chạy khi terminal khác đang build. Bản ZIP tải về cũng nằm trong `.devcache/downloads` và sẽ bị xóa cùng cache. Gỡ bộ công cụ không thu hồi quyền ứng dụng GitHub đã cấp; quản lý quyền đó riêng trên GitHub khi cần.

Nguồn: [Flutter SDK archive](https://docs.flutter.dev/install/archive), [Android command-line tools](https://developer.android.com/studio#command-line-tools-only), [Eclipse Temurin](https://adoptium.net/), [GitHub CLI releases](https://github.com/cli/cli/releases).
