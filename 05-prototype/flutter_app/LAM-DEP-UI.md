# Làm đẹp giao diện tổng quan — bước 9

Ngày 2026-10-15. Tận dụng các thư viện đã cài nhưng chưa dùng, thêm nhận diện cho app và chuyển động nhẹ. Vẫn giữ chữ lớn, nút to và chế độ giảm chuyển động cho người 50–60+.

## Thư viện

| Thư viện | Trước | Sau |
| --- | --- | --- |
| `flutter_animate` | Chỉ dùng ở bước đặt lịch | Thẻ ở Trang chủ hiện dần từ trên xuống; dấu tick “bật” lên khi đặt lịch xong |
| `flutter_svg` | Không dùng | 4 hình minh họa: Chào mừng, chưa có lịch hẹn, chưa có thông báo, gia đình |
| `table_calendar` | Không dùng | Lịch tháng ở trang Lịch hẹn, chấm cam dưới ngày có hẹn, chạm ngày để lọc |
| `animations` 3.0.0 (mới) | — | Trang mới trượt ngang và mờ dần (shared axis); chuyển tab mờ dần (fade through) |
| `flutter_launcher_icons`, `flutter_native_splash` (mới, chỉ dùng lúc build) | Icon Flutter mặc định, mở app màn trắng | Icon và màn mở app có logo MedicApp trên nền xanh |
| `google_fonts`, `cupertino_icons` | Cài nhưng không dùng | Đã gỡ. Font Be Vietnam Pro vẫn nhúng sẵn trong app, không tải qua mạng |

`skeletonizer` giữ cho bước tải giờ khám. Chưa thêm khung tải cho danh sách lịch hẹn và hồ sơ, vì dữ liệu mock có ngay và bước 4 đã quy định không thêm thời gian chờ giả; nên thêm khi nối backend thật.

## Nhận diện

- Logo: lịch có dấu chữ thập, trắng trên nền xanh `#0F766E`, cùng hình với biểu tượng thông báo. Nguồn ở `assets/brand/logo_mark.svg`, ảnh PNG cho icon và màn mở app được xuất từ đó.
- Icon Android dùng adaptive icon (nền xanh, hình trắng, có bản đơn sắc cho Android 13). Tạo lại bằng `dart run flutter_launcher_icons`.
- Màn mở app nền xanh có logo, cả Android 12 trở lên. Tạo lại bằng `dart run flutter_native_splash:create`.
- Logo do AI vẽ cho bản mẫu; khi có logo chính thức chỉ cần thay các file trong `assets/brand/` rồi chạy lại hai lệnh trên.

## Hình minh họa

Vẽ riêng cho MedicApp (SVG phẳng, màu của app, không cần ghi nguồn), nằm trong `assets/illustrations/`. Màn đọc màn hình bỏ qua hình vì chỉ để trang trí.

- **Chào mừng:** người lớn tuổi, người trẻ và điện thoại đặt lịch.
- **Chưa có lịch hẹn** (Trang chủ, Lịch hẹn): lịch trống và đồng hồ; Trang chủ nhắc bấm “Bắt đầu”.
- **Chưa có thông báo:** chuông có dấu tick.
- **Hồ sơ chỉ có một người:** cả nhà ba thế hệ, mời thêm bố mẹ, vợ chồng, con.

## Chuyển động

- Trang mới trượt ngang 30 px và mờ dần; quay lại thì ngược lại. Chuyển tab mờ dần 220 ms.
- Trang chủ: thẻ đặt lịch rồi đến các lịch hẹn hiện dần, mỗi thẻ cách nhau 60 ms.
- Đặt lịch xong: dấu tick bật lên một lần kèm câu “MedicApp sẽ nhắc trên điện thoại trước buổi khám”.
- Khi điện thoại bật giảm chuyển động hoặc dùng trình đọc màn hình (`AppMotion.reduced`), mọi hiệu ứng trên tắt, trang hiện ngay.

## Sửa thêm

- Lịch hẹn xếp theo ngày giờ khám, gần nhất trước.
- Đăng xuất xóa thông báo nhanh (snackbar) của phiên cũ, để không che nút ở màn Chào mừng.

## Kiểm tra

`test/ui_polish_test.dart` (5 test): hiệu ứng có khi bình thường và tắt khi giảm chuyển động, màn trống có hình, lịch tháng lọc theo ngày và “Xem tất cả”, dấu tick chỉ hiện khi đặt lịch thành công, gợi ý thêm người thân chỉ hiện khi có một hồ sơ.

Chưa kiểm tra: chưa build APK nên chưa xem icon và màn mở app trên máy thật; ảnh xem trước là ảnh chụp từ widget test, không thể hiện chuyển động. 8 ảnh chuẩn (golden) vẫn lệch như trước do font khác Windows và cần cập nhật trên Windows.
