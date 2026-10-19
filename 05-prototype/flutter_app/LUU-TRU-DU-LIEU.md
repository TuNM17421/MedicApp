# Bước 10: Lưu dữ liệu sức khỏe trên máy

## Người dùng thấy gì

- Đăng nhập xong, Trang chủ có thẻ **Lưu hồ sơ trên máy này?** với hai nút **Xem và đồng ý** và **Để sau**.
- Màn hình **Lưu dữ liệu sức khỏe** liệt kê những gì được lưu, lưu ở đâu, và cách rút lại. Ô "Tôi hiểu đây là dữ liệu sức khỏe nhạy cảm…" không được tick sẵn; nút **Đồng ý và lưu** chỉ bấm được sau khi tick.
- **Tài khoản → Dữ liệu sức khỏe** cho biết đang lưu từ ngày nào, và có nút **Ngừng lưu và xóa khỏi máy**.
- Đã đồng ý thì mở lại app vẫn còn tài khoản, hồ sơ và phiên đăng nhập.

## Cách hoạt động

- `lib/core/storage/local_vault.dart`: `EncryptedFileVault` ghi một file JSON mã hóa AES-256-GCM vào thư mục riêng của app. Khóa sinh ngẫu nhiên lần đầu, giữ trong `flutter_secure_storage` (Android Keystore). File không mở được (ví dụ mất khóa) thì bị xóa và app bắt đầu lại từ đầu.
- `lib/features/consent/health_consent.dart`: bản ghi đồng ý (`version`, `acceptedAt`), định dạng file (`VaultSnapshot`) và `vaultSyncProvider` ghi lại file mỗi khi tài khoản thay đổi. Chỉ tài khoản đã đồng ý được ghi; không còn ai đồng ý thì file và khóa bị xóa.
- `main.dart` đọc file trước khi mở app. Test và bản xem trước dùng `MemoryVault`, không ghi gì xuống máy.
- `android:allowBackup="false"`: bản sao lưu không mang được khóa sang máy khác, nên không sao lưu file.

## Giới hạn

- Lịch hẹn chưa được lưu; sẽ làm cùng đơn thuốc ở bước 11.
- Mật khẩu tài khoản mock nằm trong file mã hóa, chưa băm. Khi có máy chủ thật, mật khẩu sẽ không lưu trên máy.
