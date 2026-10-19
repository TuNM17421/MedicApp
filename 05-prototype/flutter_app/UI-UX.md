# Hoàn thiện UI/UX — bước 4

Ngày 2026-10-14. Tiếp tục luồng đặt lịch cơ bản; giữ nguyên footer chỉ icon và chưa làm Smart Scheduling.

## Thay đổi

- Nội dung bước mới hiện nhẹ trong 180 ms, dịch lên 6 px bằng `flutter_animate`. Chỉ có một form và một nút hành động hiện tại; không giữ bản sao của bước cũ khi chuyển cảnh. Chọn thẻ hoặc gõ thông tin không chạy lại hiệu ứng bước.
- Tải giờ khám dùng `skeletonizer`: các khối theo bố cục giờ sáng/chiều, màu thay đổi nhẹ trong 1.2 giây. Không thêm thời gian chờ giả để kéo dài hiệu ứng. Skeleton kết thúc khi có dữ liệu hoặc lỗi.
- Nhãn “Đang tải giờ khám” có live region; skeleton không nhận bấm hoặc focus và không đọc các khối trang trí thành dữ liệu. Nút tiếp tục tạm khóa khi đang tải. Sau tải, hiển thị số khung giờ còn chỗ; lỗi giữ nút thử lại của luồng trước.
- `AppMotion` đọc cả `disableAnimations` và `accessibleNavigation`. Khi một trong hai được bật, hiệu ứng bước tắt, skeleton đứng yên, thời lượng đổi màu thẻ, mở ghi chú, mở sheet thêm người khám và cuộn tới phản hồi bằng 0. Các điều khiển Material vẫn dùng hành vi hệ thống.
- Ô ngày/giờ chừa vị trí dấu chọn bên cạnh nội dung, giữ nguyên chiều cao khi chọn. Grid tăng/giảm số cột theo độ rộng và cỡ chữ, nội dung xuống dòng; không giới hạn text scale hoặc rút gọn thông tin đặt khám.
- Header nội dung đánh dấu tiêu đề cho công cụ hỗ trợ; lỗi và thông báo thay đổi có live region. Khi phát sinh lỗi, tự cuộn tới thông báo để tránh lỗi nằm ngoài vùng nhìn thấy.
- Form có thứ tự focus, nút Next/Done của bàn phím và vuốt để đóng bàn phím. Nội dung booking tránh vùng khuyết hai bên; sheet thêm người khám dùng safe area và khoảng chừa bàn phím.

Chuyển nội dung từng bước sang một `Column` cuộn để giữ trường nhập đang sửa khi cuộn ra khỏi màn hình. Danh sách trong prototype ngắn và cố định; khi tích hợp catalog lớn cần phân trang/lọc và dựng danh sách theo nhu cầu.

## Kiểm tra

`test/booking_ux_test.dart` kiểm tra hiệu ứng kết thúc, không lặp khi chọn, chế độ giảm chuyển động, vòng đời skeleton/lỗi/thử lại, semantics của loading/lựa chọn, ổn định kích thước ô, tự cuộn báo lỗi và form với bàn phím/safe area giả lập.

Luồng dịch vụ chạy trọn vẹn ở 320×640 với chữ 250% và 800×360 với chữ 200%; luồng BHYT ở chữ 200% tiếp tục nằm trong bộ kiểm tra bước 3. Đây là kích thước/cỡ chữ mô phỏng trong widget test, chưa phải đo trên thiết bị thật hoặc xác nhận tuân thủ tiêu chuẩn tiếp cận.

Ảnh chuẩn bổ sung trong `test/goldens/`:

- `booking-skeleton-360-large-text.png`: trạng thái tải tĩnh, chữ 200%.
- `booking-slots-360-large-text.png`: giờ còn chỗ, đã chọn và hết chỗ, chữ 200%.
- `preview-controls-360.png`: cập nhật dấu chọn bên cạnh nội dung. Ảnh footer không thay đổi.

Các màn kiểm tra, thanh toán và kết quả bước 3 giữ nguyên ảnh chuẩn. Chưa thử trực tiếp Android/TalkBack hoặc với người dùng thật. Dữ liệu và thanh toán tiếp tục giả lập, lưu trong phiên.

Không có log thử người dùng thật được tạo trong bước này.

Kết quả kiểm tra cục bộ 2026-10-14: analyze không có vấn đề, toàn bộ 52 test pass, APK debug build thành công. Đã dừng Gradle daemon sau build.
