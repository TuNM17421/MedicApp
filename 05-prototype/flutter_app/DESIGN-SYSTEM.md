# Nền giao diện MedicApp — bước 1

Ngày 2026-10-14. Triển khai theme, font, icon và widget dùng chung từ bố cục prototype nhánh `prototype/interactive-booking` tại commit `89c4fcd`. Chủ dự án mới duyệt bố cục; chi tiết triển khai còn có thể điều chỉnh. Chưa làm luồng đặt lịch.

## Chạy bản xem trước

Sau khi kích hoạt môi trường từ gốc repo, vào `05-prototype/flutter_app` và chạy `flutter run --route=/design-preview` với thiết bị Android để mở **Xem trước giao diện**. Nút “Xem các thành phần” cuộn đến bộ mẫu; chọn thẻ/ngày/giờ hoặc mục thanh đáy trong bộ mẫu chỉ đổi trạng thái cục bộ. Nút trợ giúp mở thông tin về bản xem trước. App chính hiện dùng [shell bước 2](NAVIGATION.md); chưa có bản nháp đặt khám, thanh toán hoặc backend.

## Tổ chức mã nguồn

| File / thư mục | Trách nhiệm |
| --- | --- |
| [app/theme/app_theme.dart](lib/app/theme/app_theme.dart) | Palette, typography, theme Material 3 và `AppTokens` |
| [core/widgets/app_icons.dart](lib/core/widgets/app_icons.dart) | Tên icon có ý nghĩa, ánh xạ sang Lucide |
| [core/widgets/app_widgets.dart](lib/core/widgets/app_widgets.dart) | Điểm import chung cho bộ widget |
| [features/design_preview](lib/features/design_preview/) | Màn hình kiểm tra thành phần, tách khỏi màn hình nghiệp vụ tương lai |
| [assets/fonts](assets/fonts/) | Be Vietnam Pro 400/500/600/700/800 và giấy phép OFL |
| [test/widget_test.dart](test/widget_test.dart) | Kiểm tra bố cục, chọn trạng thái, semantics và ảnh chuẩn |

## Theme và font

- Màu chính `#0F766E`, nền `#F7FAF8`, chữ `#16302C`, chữ phụ `#4B5563`; thẻ bo 20, vé bo 24, nút dạng viên thuốc.
- `AppTokens` cung cấp tone teal/peach/lavender/sky và các tone thông báo. Theme hiện chỉ có chế độ sáng.
- Be Vietnam Pro được khai báo trực tiếp trong `pubspec.yaml`; không gọi Google Fonts qua mạng lúc chạy. `google_fonts` vẫn được cài nhưng không cần dùng để tải font runtime.
- Font tải từ [Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/bevietnampro), giữ nguyên file TTF và [giấy phép](assets/fonts/OFL.txt). Giấy phép được đăng ký trong LicenseRegistry khi app chạy.
- Chữ nội dung 18, phụ 16, tiêu đề 20/26/28. Nội dung không khóa `TextScaler`; avatar viết tắt là hình trang trí, được loại khỏi semantics và dùng cỡ cố định. Tên đầy đủ cần xuất hiện cạnh avatar khi sử dụng.
- Đã thêm localization tiếng Việt từ SDK cho các thành phần Material.

## Các widget hiện có

| Nhóm | Widget | Hành vi |
| --- | --- | --- |
| Nền, icon | `AppSurface`, `AppIconTile`, `AppIcon` | Thẻ, nền icon và icon dùng một hệ thống |
| Nút, nhập liệu | `AppPrimaryButton`, `AppPrimaryActionBar`, `AppTextField` | Nút tối thiểu 56, trạng thái đang xử lý khóa thao tác, lỗi cạnh trường |
| Lựa chọn | `AppChoiceCard`, `AppSelectionChip`, `AppChoiceGrid` | Đã chọn, không khả dụng, nhãn đọc màn hình; lưới tự giảm số cột khi tăng chữ |
| Phản hồi | `AppStatusBanner`, `AppEmptyState`, `AppLoadingState`, `AppErrorState` | Phân biệt thông tin/cảnh báo/lỗi/thành công; loading tôn trọng giảm chuyển động |
| Thông tin | `AppReviewSection`, `AppTicketCard` | Nhóm key/value, hành động sửa có nhãn ngữ cảnh; vé thuần hiển thị, không tạo QR/giao dịch |
| Khung | `AppBrandHeader`, `AppPageHeader`, `AppFlowHeader`, `AppBottomNav` | Header và mẫu thanh đáy. Không thực hiện điều hướng hoặc quản lý tiến trình |

`AppBottomNav` phát callback theo vị trí 0–4; vị trí 2 dành cho hành động Đặt lịch. Theo chỉnh sửa của chủ dự án, thanh đáy hiện chỉ dùng icon trên một hàng, nền bo góc và nút Đặt lịch nổi ở giữa; cao 88 cộng vùng an toàn hệ thống. Tên mục vẫn có trong semantics và tooltip khi nhấn giữ, kể cả số thông báo chưa đọc. Vùng bấm mỗi mục cao 80. Chữ nội dung app vẫn tôn trọng cỡ chữ hệ thống; footer không còn nhãn chữ hoặc bố cục nhiều hàng.

Các widget nhận dữ liệu và callback từ bên ngoài; quy tắc BHYT, lịch bác sĩ, giữ giờ và thanh toán không thuộc bộ giao diện. Riverpod/go_router được tích hợp ở lớp app trong bước 2; widget giao diện vẫn độc lập với các quy tắc nghiệp vụ.

## Kiểm tra

- `flutter analyze`: Không phát hiện vấn đề.
- 12 widget/visual tests: mở preview; bố cục 360 × 800 và 412 × 915 ở chữ 100%/200%; semantics lựa chọn; không cho bấm ô hết chỗ/nút đang xử lý; thao tác chọn thẻ/giờ; bốn ảnh chuẩn.
- Đã xem trực tiếp ảnh render có font Be Vietnam Pro và icon Lucide. Ảnh ở [test/goldens](test/goldens/), gồm màn đầu và mẫu lựa chọn.
- APK debug build thành công sau thay đổi.
- Chưa thử trên điện thoại Android, bàn phím ảo thật hoặc TalkBack. Kiểm tra semantics bằng widget test chưa thay thế kiểm tra trình đọc màn hình trên thiết bị.

Golden được tạo và duyệt cho lần đầu này; thay đổi hình ảnh sau này cần xem diff trước khi cập nhật baseline.
