# Liên kết hai máy

Con cài app trên máy mình, tạo hồ sơ cho Mẹ Lan, rồi liên kết hồ sơ đó với điện thoại của mẹ. Từ lúc đó, mỗi người uống thuốc theo chuông trên máy mình, còn lịch hẹn hiện ở cả hai máy.

## Cách liên kết

1. Trên máy con, vào Hồ sơ của mẹ và chọn "Liên kết máy của Mẹ". Máy hiện mã QR và mã 8 ký tự (ví dụ `ABCD-EF23`). Mã có hiệu lực 15 phút và chỉ dùng được một lần.
2. Trên máy mẹ, cài app, đăng ký, rồi vào Tài khoản và chọn "Nhận liên kết từ người thân". Quét mã QR, hoặc gõ mã nếu không quét được.
3. Máy mẹ hiện ai đang mời và mẹ sẽ được chia sẻ những gì. Mẹ chọn có báo cho con khi quên thuốc hay không, rồi bấm Đồng ý.
4. Máy con tự chuyển sang "Đã liên kết". Trong lúc chờ, máy con hỏi lại server mỗi 3 giây.

## Sau khi liên kết

| | Máy con | Máy mẹ |
| --- | --- | --- |
| Lịch hẹn của mẹ | Thấy và đặt được | Thấy và đặt được |
| Đơn thuốc của mẹ | Vẫn xem được, không còn chuông | Có chuông báo uống thuốc |
| Mẹ quên hoặc bỏ liều | Nhận thông báo (nếu mẹ đồng ý chia sẻ) | |
| Đơn thuốc và lịch hẹn của con | Chỉ ở máy con | Không thấy |

Một số chi tiết:

- Trên màn Thuốc hôm nay của máy con, mẹ có một thẻ riêng "Thuốc của Mẹ Lan uống trên máy của Mẹ Lan". Thẻ này hiện các lần lỡ liều gần nhất.
- Một liều quá 60 phút mà chưa ghi thì tính là lỡ. Nếu sau đó mẹ ghi đã uống, máy con nhận thêm tin "đã uống (muộn)".
- Mẹ có thể tắt hoặc bật lại việc báo lỡ liều ở Tài khoản.
- Một trong hai người hủy liên kết thì chuông thuốc của mẹ quay lại máy con. Máy mẹ giữ những gì đã nhận.
- Khi hồ sơ chưa liên kết, mọi thứ chạy như trước: thuốc của mẹ vẫn kêu trên máy con.

## Giới hạn hiện tại

- Phải chạy với [backend local](../backend/FAMILY-API.md) (`--dart-define=API_BASE_URL=...`). Không có backend thì app không hiện nút liên kết.
- Chưa có thông báo đẩy (FCM/APNs). Máy con chỉ biết mẹ lỡ liều khi app đang mở: lúc mở app, lúc quay lại app và mỗi 30 giây. Server vẫn tính lỡ liều ngay cả khi máy mẹ tắt.
- Chưa thử trên hai điện thoại thật.

## Code và test

- `lib/features/family/domain/family_models.dart`: liên kết, tin lỡ liều, đọc mã QR.
- `lib/features/family/data/family_api.dart`: gọi API.
- `lib/features/family/application/family_providers.dart`: tạo mã, nhận mã, đồng bộ, đẩy lịch liều, thông báo lỡ liều.
- `lib/features/family/presentation/family_pages.dart`: thẻ trong Hồ sơ, màn mã QR, màn nhận liên kết, thẻ ở Tài khoản và Thuốc hôm nay.
- `test/family/family_link_test.dart`: 4 test, mô phỏng hai máy dùng chung một server giả.
