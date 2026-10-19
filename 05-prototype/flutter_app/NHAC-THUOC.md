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

## Chuông báo uống thuốc

Thẻ **Chuông báo uống thuốc** ở Thuốc hôm nay có công tắc bật/tắt (mặc định tắt). Đây là chỗ duy nhất xin quyền báo thức chính xác: thẻ "Lời nhắc có thể đến trễ vài phút" và nút "Bật nhắc đúng giờ" của bước 12 đã bỏ. Bật lên thì lời nhắc "Đến giờ uống" đổ chuông như đồng hồ báo thức thay vì chỉ hiện thông báo.

- **Xin quyền:** trước khi hỏi, app giải thích chuông sẽ làm gì. Sau đó lần lượt xin quyền thông báo, quyền "Báo thức và lời nhắc" (`SCHEDULE_EXACT_ALARM`) và quyền hiện trên màn hình khóa (`USE_FULL_SCREEN_INTENT`, Android 14 mở trang cài đặt riêng).
- **Khi người dùng từ chối:** không cho "Báo thức và lời nhắc" thì chuông không bật, lời nhắc vẫn là thông báo như cũ. Không cho hiện trên màn hình khóa thì chuông vẫn kêu, chỉ hiện ở thanh thông báo. Nếu sau này người dùng thu hồi quyền báo thức chính xác, app tự quay về thông báo thường.
- **Cách kêu:** kênh thông báo riêng `med_alarms` dùng nhạc chuông báo thức của máy, phát theo âm lượng báo thức (nên vẫn kêu khi để im lặng và qua chế độ Không làm phiền), lặp lại liên tục (`FLAG_INSISTENT`) đến khi bấm **Đã uống** hoặc **Nhắc lại sau 10 phút**, tự dừng sau 5 phút. Lịch đặt bằng `setAlarmClock` nên Android không hoãn để tiết kiệm pin, và hiện biểu tượng báo thức trên thanh trạng thái.
- **Màn đổ chuông** (`/med-alarm`, `med_alarm_page.dart`): mở khi chuông kêu lúc khóa máy, hoặc khi bấm vào chuông. Hiện giờ uống, "Đến giờ uống thuốc" (hoặc "Mẹ Lan: đến giờ uống thuốc"), danh sách thuốc và hai nút lớn **Đã uống** và **Nhắc lại sau 10 phút**. Bấm nút nào cũng tắt chuông. Danh sách thuốc đi theo payload của thông báo (`lines`).
- Chỉ lời nhắc đến giờ uống mới đổ chuông, và "Nhắc lại sau 10 phút" vẫn đổ chuông. Lời nhắc 30 phút sau và báo sắp hết thuốc vẫn là thông báo thường.
- Cài đặt lưu theo máy (bộ nhớ an toàn, khóa `medicapp.med_alarm`), không theo tài khoản, vì nó phụ thuộc quyền máy đã cho.
- **iOS:** dự án chưa có thư mục iOS. Khi làm iOS: iOS 26 trở lên có AlarmKit (xin quyền `NSAlarmKitUsageDescription`) cho báo thức thật như app Đồng hồ; máy cũ hơn chỉ có thông báo "Time Sensitive" với âm thanh tối đa 30 giây, hoặc "Critical Alerts" nếu Apple duyệt entitlement cho app y tế.

## Thông báo dùng chung

Plugin thông báo chỉ giữ một hàm xử lý khi bấm, nên nhắc khám (bước 8) và nhắc thuốc giờ đi qua một `NotificationHub` (`lib/core/notifications/notification_hub.dart`). Mỗi loại có dải id riêng để thay lịch của mình mà không xóa của loại kia: nhắc khám 0–999, nhắc thuốc 1000–8999, nhắc lại 10 phút 9000–9999. Payload có tiền tố `visit:` hoặc `med:`; payload nhắc khám cũ không có tiền tố vẫn mở đúng lịch hẹn.

Android 14 tắt báo thức chính xác mặc định. App khai báo `SCHEDULE_EXACT_ALARM`; khi người dùng cho phép (lúc bật chuông) thì nhắc đúng phút, nếu không thì dùng báo thức không chính xác (có thể trễ vài phút).

## Dữ liệu

Nhật ký liều (`doseLog`) lưu trong tài khoản, cùng chỗ với lịch hẹn và kết quả khám, nên được mã hóa trong kho của bước 10 khi chủ tài khoản đã đồng ý. Tài khoản khác không thấy nhật ký này. Liều bấm trên thông báo của tài khoản khác được giữ lại trong hàng chờ cho tài khoản đó.

## Sửa lỗi kèm theo

`prepClockProvider` trước đây trả giờ Việt Nam nhưng gắn cờ UTC, nên so với `DateTime` thường bị lệch 7 tiếng trên máy đặt giờ Việt Nam. Giờ nó trả giờ Việt Nam dạng giờ địa phương.

## Chưa làm

- Tóm tắt hằng tuần cho người thân. Cảnh báo lỡ liều đã có ở [Liên kết hai máy](LIEN-KET-HAI-MAY.md): khi hồ sơ đã liên kết, chuông chỉ kêu ở máy của người uống.
- Tự chỉnh giờ uống theo thói quen từng người (hiện dùng giờ cố định của từng buổi).

## Code và test

- `lib/features/meds/domain/medication.dart`: lịch uống, trạng thái liều, số thuốc còn lại, tỷ lệ uống đúng.
- `lib/features/meds/domain/med_reminder_planner.dart`: lập lịch nhắc.
- `lib/features/meds/data/med_reminder_scheduler.dart`: đặt thông báo, nút trên thông báo, hàng chờ liều.
- `lib/features/meds/application/meds_providers.dart`, `lib/app/notifications.dart`.
- `lib/features/meds/presentation/today_meds_page.dart`: màn Thuốc hôm nay và thẻ Trang chủ.
- `lib/features/meds/presentation/med_alarm_page.dart`: màn đổ chuông.
- `test/meds/medication_test.dart`: 13 test (3 test cho chuông báo, màn đổ chuông nằm trong test màn Thuốc hôm nay).
