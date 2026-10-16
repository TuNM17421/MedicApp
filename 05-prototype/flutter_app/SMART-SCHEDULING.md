# Đặt lịch thông minh — bước 5

Ngày 2026-10-15. Triển khai theo [PRD triển khai Smart Scheduling](../prd-smart-scheduling-implementation.md). Backend và cách chạy: [backend/README.md](../backend/README.md). Footer, luồng cơ bản và thanh toán giả lập giữ nguyên.

## Trải nghiệm

- **Điểm vào:** nút “Đặt lịch thông minh” dưới nút Bắt đầu ở Trang chủ, và “Chưa biết chọn khoa? Nói hoặc nhập nhu cầu” ở bước Chuyên khoa. Khi vào từ luồng cơ bản, người khám, hình thức và nơi khám đã chọn được mang theo và không hỏi lại.
- **Nói, nhập hoặc chọn:** thanh dưới có nút Nói và ô Nhập tay. Câu hỏi hiện bằng chữ kèm lựa chọn nhanh, mỗi lượt một câu.
- **Giọng nói:** bấm Nói mới xin quyền micro và bắt đầu gửi âm thanh. Thanh “Micro đang bật” ghi rõ giọng nói đang được gửi tới dịch vụ chuyển chữ, có thời lượng, “Xong lượt nói” (tùy chọn) và Dừng. Chữ tạm hiện nghiêng khi đang nói; hết lượt được nhận bằng khoảng lặng khoảng 1,7 giây rồi tự xử lý, không có bước duyệt transcript hay nút Gửi. Có thể nói tiếp khi đang xử lý; lượt cũ bị thay. Micro tắt khi hiện câu hỏi hoặc đề xuất, khi app vào nền và khi rời màn.
- **Đề xuất (SS05):** một bản tổng quan gồm người khám, hình thức, nơi khám, chuyên khoa kèm lý do gợi ý và nhu cầu đã nói, bác sĩ, ngày giờ, phí và người nhận thông báo. Mỗi phần có Sửa; phần vừa đổi ghi “vừa đổi”; có Hoàn tác thay đổi vừa rồi. Giờ là **giờ còn chỗ sớm nhất** phù hợp ngày/buổi đã chọn, không phải “ít chờ nhất”.
- **Xác nhận (SS06):** “Xác nhận và tiếp tục thanh toán” chỉ bật khi đủ thông tin, không đang nghe hoặc xử lý và liên hệ hợp lệ. App kiểm tra lại tuổi/khoa, BHYT/cơ sở, giờ và phí qua `BookingRepository`, rồi nạp bản nháp một lần vào luồng đặt lịch ở bước Thanh toán. Nếu giờ vừa hết chỗ, app đề xuất giờ khác và yêu cầu xác nhận lại. Người dùng vẫn tự chọn cách thanh toán và bấm thanh toán.
- **Thoát và lỗi (SS07):** “Đặt lịch từng bước” luôn có, chuyển các lựa chọn còn hợp lệ sang luồng cơ bản. Lỗi kết nối, quyền micro, giới hạn hoặc AI đều giữ dữ liệu đã có và còn lựa chọn nhanh/nhập tay.
- **Cần hỗ trợ y tế (SS08):** dừng đặt lịch thường, khuyên gọi cấp cứu 115 hoặc đến cơ sở y tế gần nhất. Nội dung này và quy tắc nhận diện cần chuyên môn duyệt trước khi dùng thật.
- **Mô phỏng AI:** khi backend chạy không có key, màn hình hiện nhãn “Mô phỏng AI” và micro báo chưa hỗ trợ giọng nói.

## Mã nguồn

| Thư mục | Nội dung |
| --- | --- |
| `lib/features/smart/domain` | Câu trả lời server, trường, câu hỏi, sự kiện audio, đề xuất |
| `lib/features/smart/data` | `HttpSmartGateway` (HTTP + WebSocket tới backend), `RecordVoiceCapture` (PCM16 mono 24 kHz, chỉ trong bộ nhớ) |
| `lib/features/smart/application` | `SmartController` (phiên, version, đề xuất, xác nhận, micro), `SilenceDetector` |
| `lib/features/smart/presentation` | `SmartPage` và các sheet sửa |
| `lib/app/config/app_config.dart` | `API_BASE_URL`, mặc định `http://127.0.0.1:8080` |

`BookingHandoff` trong `booking_providers.dart` bàn giao bản nháp: vào từ Trang chủ thì `BookingController` mới đọc một lần khi mở `/booking`; vào từ bước Chuyên khoa thì cập nhật luồng đang mở bằng `applyHandoff`. Không đổi provider trong lúc provider khác đang build.

Android: thêm quyền `RECORD_AUDIO` (chỉ xin khi bấm Nói) và `INTERNET`. Bản debug cho phép HTTP tới `127.0.0.1`/`localhost` để dùng `adb reverse`; bản release giữ mặc định chỉ HTTPS. Package mới: `http`, `web_socket_channel`, `record`.

## Kiểm tra

- `test/smart/smart_controller_test.dart`: ngữ cảnh không gửi tên, đề xuất theo giờ sớm nhất của buổi, phản hồi cũ không ghi đè (AC06), xác nhận và bàn giao (AC09), mất slot khi xác nhận (AC10), sửa và Hoàn tác (AC07), khẩn (AC14), lỗi kết nối (AC13), từ chối quyền micro (AC04), mock không giả nhận giọng, luồng giọng nói đủ bước (AC01), dọn micro/phiên khi đóng (AC12), quay về luồng cơ bản (AC16), bàn giao nguyên tử, `SilenceDetector`, đối chiếu catalog với backend.
- `test/smart/smart_flow_test.dart`: Trang chủ → nhập → đề xuất → thanh toán → kết quả; từ bước Chuyên khoa giữ ngữ cảnh rồi quay lại đúng bước Thanh toán; đề xuất và thanh micro ở 360 px chữ 200%.
- `test/smart/backend_contract_test.dart`: chạy backend Node thật ở chế độ mock (nếu đã `npm ci`) và đi qua HTTP/WebSocket.

Kết quả 2026-10-15 trên Linux (Flutter 3.47.7): `flutter analyze` sạch; bộ kiểm tra có 77 test (thêm 22 test Smart và 3 test sửa lỗi Quay lại); mọi test không phải ảnh chuẩn đều pass. 8 test ảnh chuẩn lệch 1–5% pixel do render font khác Windows nơi ảnh được tạo, riêng `shell-home-1x.png` còn đổi thật vì Trang chủ có thêm nút “Đặt lịch thông minh”. Cần chạy `flutter test --update-goldens` trên máy Windows để cập nhật và xem lại ảnh Trang chủ.

**Chưa kiểm chứng:** chưa build APK (môi trường thực hiện không có Android SDK), chưa thử trên OPPO/TalkBack, chưa gọi OpenAI bằng key thật, chưa đo ngưỡng khoảng lặng với người nói chậm hoặc nơi ồn. Chưa làm “Dùng vị trí hiện tại” (PRD đợt 4): hiện người dùng chọn hoặc nói khu vực/cơ sở; catalog chưa có tọa độ kiểm chứng nên không có nhãn “gần nhất”.

Code, test và tài liệu của bước này do AI tạo theo yêu cầu chủ dự án; không có log thử người dùng thật.
