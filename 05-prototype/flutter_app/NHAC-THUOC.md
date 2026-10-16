# Bước 12: Nhắc uống thuốc

Khi bác sĩ gửi đơn thuốc (bước 11), app tự lập lịch uống cho từng thuốc, nhắc đúng giờ, ghi lại liều đã uống hoặc bỏ, và báo khi sắp hết thuốc. Mọi thứ chạy trên điện thoại, không có máy chủ.

## Người dùng thấy gì

- **Trang chủ** có thẻ "Thuốc hôm nay" khi có thuốc phải uống trong ngày: số liều còn lại, giờ liều tiếp theo, số liều đã lỡ (thẻ chuyển sang màu đỏ).
- **Thuốc hôm nay** (`/home/meds`):
  - Tóm tắt "Đã uống 2/5 liều", liều lỡ, giờ liều tiếp theo.
  - Liều xếp theo từng người trong tài khoản (Thuốc của bạn, Mẹ Lan…), mỗi liều có giờ, buổi, số viên, trước/sau ăn và trạng thái: Chưa đến giờ, Đến giờ uống, Đã uống lúc HH:mm, Bỏ liều (lý do), Lỡ liều.
  - Nút **Đã uống** và **Bỏ liều**. Bỏ liều hỏi lý do: Quên uống, Hết thuốc, Thấy khó chịu, Lý do khác. Ghi nhầm thì bấm **Hoàn tác**.
  - Thẻ **Sắp hết thuốc** khi còn 5 ngày thuốc trở xuống, có nút **Đặt lịch tái khám**.
  - Lịch sử 4 tuần cho từng người: mỗi ngày một ô, xanh là uống đủ, cam là lỡ một phần, đỏ là không uống; kèm tỷ lệ uống đúng.
  - Nếu điện thoại không cho báo thức chính xác, có thẻ "Lời nhắc có thể đến trễ vài phút" với nút **Bật nhắc đúng giờ** mở trang cài đặt của Android.

## Lời nhắc

| Loại | Khi nào | Nội dung |
|---|---|---|
| Đến giờ uống | Giờ của buổi: sáng 7:00, trưa 11:30, chiều 16:00, tối 19:00 | "Đến giờ uống thuốc" hoặc "Mẹ Lan: đến giờ uống thuốc"; các thuốc cùng giờ của một người gộp một thông báo |
| Nhắc lại | 30 phút sau, chỉ khi liều chưa được ghi | "Bạn đã uống thuốc 07:00 chưa?" |
| Sắp hết thuốc | 8:30 sáng ngày còn 5 ngày thuốc | "Sắp hết Metformin", gợi ý đặt lịch tái khám |

- Thông báo có hai nút **Đã uống** và **Nhắc lại sau 10 phút**, bấm được mà không cần mở app. "Đã uống" ghi liều vào hàng chờ trong bộ nhớ an toàn của máy và hủy lời nhắc lại; app chuyển vào lịch sử khi mở lại hoặc quay lại màn hình.
- Lịch nhắc đặt trước 48 giờ và được tính lại mỗi khi mở app, quay lại app hoặc ghi một liều.
- Liều có giờ trước lúc kê đơn trong ngày đầu không tính. Liều quá 60 phút chưa ghi được tính là lỡ.
- Số thuốc còn lại = số lượng trong đơn trừ các liều đã uống.
- Thông báo ẩn tên thuốc trên màn hình khóa (`visibility: private`).

## Thông báo dùng chung

Plugin thông báo chỉ giữ một hàm xử lý khi bấm, nên nhắc khám (bước 8) và nhắc thuốc giờ đi qua một `NotificationHub` (`lib/core/notifications/notification_hub.dart`). Mỗi loại có dải id riêng để thay lịch của mình mà không xóa của loại kia: nhắc khám 0–999, nhắc thuốc 1000–8999, nhắc lại 10 phút 9000–9999. Payload có tiền tố `visit:` hoặc `med:`; payload nhắc khám cũ không có tiền tố vẫn mở đúng lịch hẹn.

Android 14 tắt báo thức chính xác mặc định. App khai báo `SCHEDULE_EXACT_ALARM`; khi người dùng cho phép thì nhắc đúng phút, nếu không thì dùng báo thức không chính xác (có thể trễ vài phút).

## Dữ liệu

Nhật ký liều (`doseLog`) lưu trong tài khoản, cùng chỗ với lịch hẹn và kết quả khám, nên được mã hóa trong kho của bước 10 khi chủ tài khoản đã đồng ý. Tài khoản khác không thấy nhật ký này. Liều bấm trên thông báo của tài khoản khác được giữ lại trong hàng chờ cho tài khoản đó.

## Sửa lỗi kèm theo

`prepClockProvider` trước đây trả giờ Việt Nam nhưng gắn cờ UTC, nên so với `DateTime` thường bị lệch 7 tiếng trên máy đặt giờ Việt Nam. Giờ nó trả giờ Việt Nam dạng giờ địa phương.

## Chưa làm

- Người thân nhận cảnh báo khi lỡ liều và tóm tắt hằng tuần: bước 13–14, sau khi có liên kết hồ sơ giữa hai điện thoại.
- Tự chỉnh giờ uống theo thói quen từng người (hiện dùng giờ cố định của từng buổi).

## Code và test

- `lib/features/meds/domain/medication.dart`: lịch uống, trạng thái liều, số thuốc còn lại, tỷ lệ uống đúng.
- `lib/features/meds/domain/med_reminder_planner.dart`: lập lịch nhắc.
- `lib/features/meds/data/med_reminder_scheduler.dart`: đặt thông báo, nút trên thông báo, hàng chờ liều.
- `lib/features/meds/application/meds_providers.dart`, `lib/app/notifications.dart`.
- `lib/features/meds/presentation/today_meds_page.dart`: màn Thuốc hôm nay và thẻ Trang chủ.
- `test/meds/medication_test.dart`: 10 test.
