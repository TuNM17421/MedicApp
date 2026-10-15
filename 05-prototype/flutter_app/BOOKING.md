# Luồng đặt lịch cơ bản — bước 3

Luồng này đã được hoàn thiện thêm ở [bước 4 — UI/UX](UI-UX.md): animation nhẹ, skeleton, giảm chuyển động, phản hồi lỗi và kiểm tra chữ lớn. Phạm vi nghiệp vụ bên dưới giữ nguyên.

Ngày 2026-10-14. Triển khai theo PRD và bố cục prototype đã duyệt. Giữ footer chỉ icon của bước trước. Chưa triển khai Smart Scheduling.

## Cách dùng

Từ Trang chủ, bấm **Bắt đầu** hoặc nút Đặt lịch giữa footer:

1. Chọn khám BHYT hoặc khám dịch vụ.
2. Chọn người khám; có thể thêm hồ sơ bằng tên, ngày sinh, quan hệ.
3. Chọn cơ sở, chuyên khoa và bác sĩ đích danh hoặc bác sĩ còn lịch.
4. Chọn ngày và giờ còn chỗ. Có ngày mô phỏng hết lịch và các giờ không khả dụng.
5. Kiểm tra thông tin, sửa từng phần, nhập người nhận thông báo và ghi chú tùy chọn.
6. Chọn trả tại viện, ví điện tử hoặc thẻ theo hình thức/cơ sở; xác nhận thanh toán giả lập và xem kết quả.

Hồ sơ duyệt ở tab Hồ sơ và người khám của đơn là hai lựa chọn riêng. Không mặc định người khám. Các cơ sở, bác sĩ, mức phí, hồ sơ và lịch đều là dữ liệu giả định, không kết nối MyVinmec hoặc bệnh viện. Bác sĩ còn lịch được chọn theo khả dụng giả lập, không có phân tích triệu chứng hoặc xếp hạng AI.

Luồng đặt lịch che footer để dành chỗ cho một nút hành động chính. Header hiển thị tiến độ 6 bước; cơ sở/chuyên khoa/bác sĩ cùng thuộc bước 3. Back quay lại trong luồng; từ đầu hoặc kết quả sẽ đóng luồng. Khi gửi giao dịch, khóa thao tác lặp và Back. Danh sách/chi tiết lịch hẹn ở `/home/appointments` và `/home/appointments/:id` vẫn thuộc shell và có footer.

## Quy tắc dữ liệu

- Đổi cơ sở: giữ chuyên khoa nếu được hỗ trợ; chọn lại bác sĩ và giờ.
- Đổi chuyên khoa: chọn lại bác sĩ và giờ. Nhi khoa chỉ khả dụng đến 15 tuổi theo quy tắc **mô phỏng**.
- Đổi người khám: xóa ghi chú của người cũ; xóa chuyên khoa/giờ nếu không phù hợp tuổi.
- Đổi sang BHYT tại cơ sở không hỗ trợ: chọn lại cơ sở và phần phụ thuộc. BHYT chỉ trả tại viện; phí đặt lịch 0đ không khẳng định miễn viện phí hoặc được hưởng BHYT.
- Khi sửa xong, về trang Kiểm tra nếu thông tin đủ; nếu thiếu, đến lựa chọn cần bổ sung.
- Kiểm tra lại giờ trước thanh toán và khi gửi đơn. Giờ vừa hết chỗ đưa về chọn giờ, giữ thông tin còn hợp lệ.
- Kết quả tải giờ cũ không ghi đè ngày vừa chọn. Lỗi tải có nút thử lại.

## Thanh toán mô phỏng

Không mở cổng thanh toán, không nhập thông tin thẻ, không thu tiền thật. Repository trả một kết quả cho mỗi mã bản nháp; không tạo lại giao dịch đã thành công hoặc đang chờ. Ledger thay thế kết quả theo ID để tránh hiển thị trùng.

| Kết quả | Hành vi |
| --- | --- |
| Thành công / trả tại viện | Có mã lịch. Trả tại viện vẫn ghi rõ chưa thanh toán. |
| Thất bại xác định | Không có mã lịch; có thể thử lại hoặc đổi cách thanh toán. |
| Chưa rõ thanh toán | Không khẳng định có lịch; chỉ kiểm tra trạng thái, không thanh toán lại. Sau hai lần kiểm tra mô phỏng sẽ xác nhận. |
| Đã nhận thanh toán, chưa xác nhận lịch | Hiển thị mã giao dịch, không hiển thị mã lịch. Chỉ kiểm tra trạng thái hoặc mở trợ giúp; chờ phía cơ sở xác nhận mô phỏng. |

Để thử nhánh lỗi trong bản debug: **Trợ giúp → Kịch bản thử đặt lịch** (`/booking-demo`). Chọn kết quả thanh toán, lỗi tải giờ một lần/đơn hoặc giờ vừa hết chỗ một lần/đơn. Với nhánh nhận tiền chưa có lịch, bật xác nhận cơ sở rồi quay lại lịch hẹn để kiểm tra. Lựa chọn trả tại viện luôn bỏ qua kịch bản thanh toán online. Đây là màn dành cho người duyệt, không nằm trong form bệnh nhân.

## Mã và giới hạn

- `lib/features/booking/domain`: Model bản nháp, bước, phiếu và trạng thái.
- `data`: Catalog giả định và interface/mock repository thay được bằng API sau này.
- `application`: Riverpod cho bản nháp, xử lý phụ thuộc, dữ liệu bất đồng bộ, ledger và kiểm tra trạng thái.
- `presentation`: Form đặt lịch, lịch hẹn, kết quả và màn kịch bản thử.

Bản nháp chỉ sống trong route đặt lịch; đóng route sẽ bỏ bản nháp. Hồ sơ thêm và lịch hẹn tồn tại trong phiên app, mất khi khởi động lại. Chưa có đăng nhập, phân quyền người thân, lưu bền, giữ slot thật, BHYT thật, thông báo thật hoặc giao dịch thật. Không có dữ liệu phỏng vấn/người dùng thật trong source. Khi có backend cần xác thực, idempotency phía server và đối soát giao dịch; khóa UI không thay thế các cơ chế đó.

## Kiểm tra

Chạy từ thư mục app sau khi kích hoạt môi trường:

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

Test trạng thái bao phủ luồng dịch vụ/BHYT, sửa dữ liệu phụ thuộc, độ tuổi, slot mất, lỗi tải, phản hồi đến muộn, gửi lặp, thanh toán lỗi/chờ và giữ ledger khi mở đơn mới. Widget test thao tác luồng đầy đủ, thêm người khám, kiểm tra giao dịch và luồng BHYT ở chữ 200%. Golden ở `test/goldens/booking-*.png` ghi lại màn kiểm tra, thanh toán và kết quả. Các test dùng ngày cố định để tái lập. Chưa kiểm tra trực tiếp trên Android, TalkBack hoặc với người dùng thật.

Code, dữ liệu giả định, tài liệu và test của bước này do AI tạo theo yêu cầu chủ dự án; không phải log thử người thật.

Kết quả kiểm tra cục bộ ngày 2026-10-14: analyze không có vấn đề, toàn bộ 42 test pass, APK debug build thành công. Gradle daemon đã được dừng sau build.
