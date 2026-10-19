# Khung điều hướng và trạng thái — bước 2

Ngày 2026-10-14. Bước này nối shell các tab với `go_router` và trạng thái giao diện với Riverpod. Bố cục dựa trên prototype `prototype/interactive-booking` tại `89c4fcd`; chưa xây các bước đặt lịch.

## Trải nghiệm hiện tại

App mở ở Trang chủ với header xanh, thẻ Đặt lịch và lối tắt Lịch hẹn/Trợ giúp. Thanh đáy gồm bốn tab và một hành động ở giữa:

| Vị trí thanh đáy | Vai trò | Đường dẫn |
| --- | --- | --- |
| 0 — Trang chủ | Nhánh 0 | `/home`, `/home/appointments` |
| 1 — Hồ sơ | Nhánh 1 | `/profiles`, `/profiles/:id` |
| 2 — Đặt lịch | Hành động trên navigator gốc, không phải tab | `/booking` |
| 3 — Thông báo | Nhánh 2 | `/notifications`, `/notifications/:id` |
| 4 — Tài khoản | Nhánh 3 | `/account` |

- `StatefulShellRoute.indexedStack` giữ trang con và trạng thái cuộn của từng tab khi chuyển sang tab khác. Bấm lại tab đang chọn đưa tab đó về trang đầu.
- Footer được tinh gọn theo phản hồi chủ dự án: chỉ icon trên một hàng, tab được chọn có nền xanh nhạt và nút Đặt lịch nổi ở giữa. Nhấn giữ để hiện tên; TalkBack vẫn đọc tên và trạng thái, badge thông báo vẫn cập nhật. Nội dung các trang không bị giới hạn phóng chữ.
- Back trên trang con quay về cấp trước. Back ở gốc tab khác chuyển về nhánh Trang chủ. Ở gốc Trang chủ, app để hệ điều hành xử lý Back.
- `/booking` hiện chỉ là màn thông báo chưa khả dụng; không có form, bản nháp, giữ giờ hoặc thanh toán. Mở bằng `push`, che thanh đáy, đóng lại trả về đúng trang trước. Nếu mở trực tiếp không có lịch sử thì nút quay lại đưa về Trang chủ.
- `/help` và `/design-preview` cũng nằm trên navigator gốc, không kèm thanh đáy. Màn xem trước bước 1 được giữ để kiểm tra widget, không nằm trong điều hướng người dùng thường.
- Đường dẫn sai có trang phục hồi. ID hồ sơ/thông báo không tồn tại có trạng thái trống, không tạo lỗi tra cứu không được xử lý.

## Riverpod quản lý gì?

| Provider | Nội dung |
| --- | --- |
| `profileCatalogProvider` | Danh sách hồ sơ giả định, bất biến |
| `activeProfileIdProvider` | Hồ sơ đang chọn tại danh sách; kiểm tra ID khi thay đổi |
| `activeProfileProvider` | Hồ sơ tương ứng để UI hiển thị |
| `notificationFeedProvider` | Thông báo giả định; đánh dấu từng mục hoặc toàn bộ đã đọc |
| `unreadCountProvider` | Số chưa đọc suy ra từ danh sách, cập nhật badge và nhãn đọc màn hình |
| `appRouterProvider` | Vòng đời router; dispose cùng scope, không phụ thuộc trạng thái hồ sơ/thông báo |

State không lưu tab đang chọn riêng trong Riverpod: router là nguồn duy nhất cho nhánh hiện tại để tránh hai trạng thái lệch nhau. Cập nhật thông báo không tạo lại router hoặc làm mất lịch sử.

Hồ sơ đang chọn là tùy chọn duyệt danh sách; mở trực tiếp `/profiles/:id` hiển thị theo ID của đường dẫn và không tự thay lựa chọn đó. Đây chưa phải người khám trong một bản đặt lịch. Khi triển khai booking cần trạng thái và bước xác nhận riêng.

Các dữ liệu hiện tại hoàn toàn giả định, chỉ ở bộ nhớ trong `ProviderScope`; khởi động lại phiên sẽ reset. Chưa có xác thực, phân quyền người thân, lưu bền, repository/API hoặc push notification. Mở chi tiết thông báo hợp lệ sẽ đánh dấu đã đọc sau frame đầu; ID không hợp lệ không thay đổi số chưa đọc.

## Mã nguồn

- [main.dart](lib/main.dart): Khởi tạo ProviderScope, MaterialApp.router, theme và tiếng Việt.
- [app_router.dart](lib/app/router/app_router.dart): Router và các nhánh/navigator gốc.
- [app_routes.dart](lib/app/router/app_routes.dart): Đường dẫn và quy tắc back-or-home.
- [app_shell.dart](lib/app/app_shell.dart): Nối tab với nhánh, hành động Đặt lịch, Back và badge.
- [app_state.dart](lib/app/state/app_state.dart): Model/provider/controller trạng thái trong phiên.
- [app_page_body.dart](lib/core/widgets/app_page_body.dart): Khung trang cuộn và thẻ liên kết dùng chung.
- [features](lib/features/): Trang chủ, hồ sơ, thông báo, tài khoản và trang hỗ trợ.

Khai báo `MaterialPage` từ `flutter/material.dart` tường minh để dùng đúng hệ theme/chuyển trang hiện tại. `go_router` 18 có adapter cho `material_ui`; dự án chưa chuyển toàn bộ widget sang thư viện đó.

## Chạy và kiểm tra

Từ thư mục app sau khi kích hoạt môi trường:

```powershell
flutter run
flutter test --no-pub
flutter analyze --no-pub
flutter build apk --debug --no-pub
```

Để mở lại bộ mẫu bước 1 khi khởi chạy:

```powershell
flutter run --route=/design-preview
```

Các đường dẫn trên là route nội bộ. Chưa cấu hình Android App Links hoặc liên kết web xác thực của hệ điều hành.

Kiểm tra tự động gồm 27 test toàn dự án:

- 3 test state: chọn hồ sơ, thao tác read idempotent/bất biến và tách biệt giữa các phiên.
- 12 test navigation/visual: lịch sử riêng từng tab, Back, badge/router ổn định, overlay Đặt lịch, route mở trực tiếp, ID/đường dẫn sai, bố cục 360/412 ở chữ 100%/200% và hai ảnh chuẩn của shell.
- 12 test thành phần bước 1, gồm bốn ảnh chuẩn và semantics lựa chọn, tiếp tục pass.

`flutter analyze` không phát hiện vấn đề; cả 27 test và so sánh golden đều pass; `flutter build apk --debug --no-pub` thành công. Ảnh shell đã được xem trực tiếp tại [test/goldens](test/goldens/). Chưa thử trên điện thoại thật, TalkBack hoặc người dùng nghiên cứu; mô phỏng Back trong widget test chưa thay thế kiểm tra thao tác Back trên thiết bị.

## Cập nhật sau bước 3

Mô tả màn đặt lịch chưa khả dụng phía trên là trạng thái bàn giao bước 2. Hiện `/booking` mở luồng cơ bản sáu bước; `/home/appointments/:id` xem kết quả trong phiên. Hồ sơ có thể thêm từ bước chọn người khám. `bookingSessionProvider` giữ bản nháp riêng và tự dispose khi đóng route; `appointmentsProvider` giữ ledger xuyên các lần mở luồng trong cùng phiên. Xem [BOOKING.md](BOOKING.md) cho quy tắc sửa và thanh toán mô phỏng. Footer giữ nguyên thiết kế chỉ icon.
