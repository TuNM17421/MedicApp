# Thông báo nhắc khám trên điện thoại — bước 8

Ngày 2026-10-15. Ngoài lưu ý trong app (bước 7), app đặt lịch **thông báo trên điện thoại** cho mỗi lịch hẹn sắp tới, kể cả khi app đã đóng.

Đây là **thông báo cục bộ** (`flutter_local_notifications`): điện thoại tự đặt giờ báo, không có máy chủ push, hồ sơ không gửi đi đâu. Giữ đúng quy tắc không kết nối dịch vụ thật. Khi có backend thật có thể chuyển sang push (FCM) mà vẫn dùng chung bộ quy tắc chọn giờ.

## Khi nào báo

Mỗi lịch hẹn có tối đa 3 thông báo, giờ Việt Nam:

| Thông báo | Khi nào có | Giờ báo |
| --- | --- | --- |
| **Nhắc sớm** | Có kiêng từ 24 tiếng trở lên (rượu bia trước xét nghiệm mỡ máu, acid uric) | 09:00 ngày trước khi bắt đầu kiêng, tức khoảng **2 ngày trước** buổi khám |
| **Nhắc chuẩn bị** | Mọi lịch hẹn; nội dung là các mốc nhịn ăn, ngừng uống, không cà phê | Mốc muộn nhất còn cách lúc bắt đầu kiêng ít nhất 1 tiếng, theo thứ tự: **07:00 sáng cùng ngày** (chỉ lịch buổi chiều), **17:00 chiều hôm trước**, **08:00 sáng hôm trước** |
| **Nhắc trước khi đi** | Mọi lịch hẹn | 2 tiếng trước giờ khám, không sớm hơn 06:00 |

Ví dụ:

- Lịch Nội tiết 08:00 sáng, nhịn ăn 8 tiếng (từ nửa đêm): nhắc **17:00 chiều hôm trước**, rồi 06:00 sáng hôm khám.
- Lịch Cơ Xương Khớp 14:30 chiều, gút (nhịn 4 tiếng, kiêng rượu 24 tiếng): nhắc sớm **09:00 hai ngày trước**, nhắc chuẩn bị **07:00 sáng hôm khám** (bắt đầu nhịn 10:30), nhắc đi 12:30.
- Lịch nội soi 07:00 sáng (nhịn 6 tiếng từ 01:00): 17:00 chiều hôm trước.

Đặt lịch sát giờ: mốc nào đã qua thì bỏ. Nếu mọi mốc đã qua mà vẫn chưa tới giờ bắt đầu kiêng, app báo ngay (sau 1 phút). Lịch đã qua, lịch thanh toán lỗi hoặc khi đăng xuất thì hủy hết thông báo.

## Nội dung theo người khám

- **Gọi đúng người:** “Bạn…” cho hồ sơ bản thân; người thân ghi quan hệ và tên, kèm tuổi khi là trẻ em (dưới 16) hoặc người cao tuổi (từ 60): “Mẹ Phạm Thị Lan (78 tuổi)…”, để người nhận biết đang nhắc cho ai.
- **Người cao tuổi:** nên có người nhà đi cùng, mang thuốc đang dùng và kính đọc sách; khi nhịn ăn, nếu mệt, chóng mặt, vã mồ hôi thì báo ngay. Nội soi gây mê: cần người nhà đưa về, không tự lái xe.
- **Trẻ em:** trẻ khó nhịn lâu, người lớn trông bé và hỏi bác sĩ thời gian nhịn hợp với tuổi; nhắc người lớn đưa bé đi và mang sổ khám của bé.
- **Phụ nữ 15–49 tuổi** khi phải nhịn ăn hoặc làm thủ thuật: nếu đang mang thai hoặc cho con bú, báo bác sĩ trước.
- **Bảo hiểm:** lịch BHYT nhắc mang thẻ BHYT.

Các ý theo tuổi và giới cũng hiện trong mục “Chuẩn bị trước khi khám” của app.

## Định dạng thông báo

Bố cục theo [hướng dẫn thông báo của Android](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications) và [thông báo mở rộng](https://developer.android.com/training/notify-user/expanded): tiêu đề khoảng 30 ký tự chứa điều quan trọng nhất, dòng nội dung khoảng 40 ký tự không lặp tiêu đề, tối đa 3 nút, không nhắc lại tên app.

| Phần | Nội dung | Ví dụ |
| --- | --- | --- |
| Dòng đầu (header) | Lịch của ai và khoa nào | `MedicApp • Mẹ Lan · Cơ Xương Khớp • 09:00` |
| Tiêu đề | Việc cần làm và từ lúc nào | “Nhịn ăn từ nửa đêm nay”, “Từ chiều mai: kiêng rượu bia”, “Khám lúc 08:00 sáng nay” |
| Dòng dưới (thu gọn) | Giờ khám, hoặc nơi khám khi sắp đi | “Khám lúc 08:00 sáng mai” |
| Mở rộng | Mỗi dòng một mốc, nhãn in đậm: các mốc giờ theo thứ tự, giờ khám, “Để chuẩn bị”, tối đa 2 dòng “Lưu ý” theo tuổi/giới; lúc sắp đi là “Nơi khám”, “Mang theo”, “Nhớ” | “**Nửa đêm nay:** Ngừng ăn, chỉ uống nước lọc” |
| Nút | “Xem hướng dẫn” mở chi tiết lịch hẹn; “Đã hiểu” tắt thông báo. Chạm vào thông báo cũng mở chi tiết lịch hẹn | |

Khác:

- Biểu tượng thanh trạng thái riêng (hình trắng, chữ thập trong khung), màu nhấn xanh của app; trước đây dùng icon app nên hiện thành ô vuông trắng.
- Giờ trong nội dung tính theo lúc thông báo hiện ra (“sáng mai”, “chiều nay”), không theo lúc đặt lịch.
- Loại “nhắc nhở” (`reminder`) để Android xếp đúng; tự biến mất 1 tiếng sau giờ khám.
- Trên màn hình khóa chỉ hiện tên app, nội dung sức khỏe chỉ hiện khi mở khóa.
- Dùng kiểu chữ dài (BigText) với HTML thay vì kiểu danh sách (Inbox), vì Inbox cắt mỗi dòng còn một hàng, dễ mất giờ hoặc lời dặn.

## Trong app

Chi tiết lịch hẹn có mục **“Nhắc trên điện thoại”** liệt kê giờ từng thông báo. Nếu người dùng chặn thông báo, mục này báo rằng điện thoại sẽ không nhắc và cần bật lại trong Cài đặt.

## Cấu hình Android

- Quyền `POST_NOTIFICATIONS` (Android 13+, app hỏi khi có lịch đầu tiên) và `RECEIVE_BOOT_COMPLETED` (đặt lại sau khi khởi động máy).
- Receiver của plugin trong `AndroidManifest.xml`; bật core library desugaring trong `android/app/build.gradle.kts`.
- Kênh thông báo “Nhắc lịch khám”, mức ưu tiên cao. Dùng báo thức không chính xác tuyệt đối (`inexactAllowWhileIdle`), nên Android có thể báo trễ vài phút để tiết kiệm pin; không cần quyền báo thức chính xác.

## Mã nguồn

- `lib/features/visit_prep/reminder_planner.dart`: chọn giờ và soạn nội dung (thuần Dart, dễ test).
- `lib/features/visit_prep/reminder_scheduler.dart`: danh sách nhắc của tài khoản đang đăng nhập và đồng bộ với lịch thông báo của điện thoại.
- `test/visit_prep/reminder_planner_test.dart`: 9 test cho các mốc giờ, đặt lịch sát giờ, nội dung theo tuổi/giới, định dạng HTML và đồng bộ khi đăng nhập/đăng xuất.

## Chưa kiểm tra

- Chưa build APK trong môi trường này, chưa thử thông báo thật trên máy Android. Ảnh khay thông báo trong bản xem trước là mô phỏng; mỗi hãng (Samsung, Xiaomi…) vẽ thông báo hơi khác.
- Một số hãng (Xiaomi, Oppo…) chặn báo thức nền mạnh; có thể cần hướng dẫn người dùng tắt tối ưu pin cho app.
- Nội dung là bản mẫu, cần bác sĩ duyệt trước khi dùng thật.
