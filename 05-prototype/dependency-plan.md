# Thư viện Flutter và thứ tự triển khai

Ngày 2026-10-14. Chủ dự án yêu cầu cài toàn bộ các thư viện đã đề xuất, nhưng triển khai tính năng dần. Các package đã được thêm vào `flutter_app/pubspec.yaml`; phiên bản resolve cụ thể được lưu trong `pubspec.lock`. Đã thực hiện bước 1: theme, font Be Vietnam Pro offline, Lucide và widget chung. Xem [kết quả bước 1](flutter_app/DESIGN-SYSTEM.md). Chưa triển khai luồng nghiệp vụ.

| Package | Phiên bản resolve | Mục đích dự kiến |
| --- | --- | --- |
| google_fonts | 9.0.0 | Tinh chỉnh typography; đóng gói Be Vietnam Pro offline khi triển khai |
| lucide_icons_flutter | 3.1.25 | Icon thống nhất cho các tác vụ |
| flutter_animate | 4.5.2 | Chuyển trạng thái nhẹ, tôn trọng giảm chuyển động |
| skeletonizer | 3.0.0 | Loading danh sách cơ sở, bác sĩ, giờ khám |
| flutter_svg | 2.3.0 | SVG và illustration khi có asset được duyệt |
| intl | 0.20.3 | Ngày, giờ và tiền Việt Nam |
| table_calendar | 3.3.0 | Lịch tháng bổ sung nếu cần; không thay thẻ chọn ngày mặc định |
| go_router | 18.0.2 | Điều hướng các tab và luồng đặt khám riêng |
| flutter_riverpod | 3.4.3 | Bản nháp đặt khám và trạng thái dữ liệu bất đồng bộ |

## Triển khai theo từng đợt

**Cập nhật:** Bước 2 đã tích hợp go_router và Riverpod vào shell các tab và trạng thái hồ sơ/thông báo, chưa tạo luồng hoặc trạng thái bản nháp đặt khám. Xem [chi tiết bước 2](flutter_app/NAVIGATION.md).

1. **Nền thị giác:** Theme/token Material, typography Be Vietnam Pro đóng gói, icon và widget chung. Lấy bố cục prototype nhánh `prototype/interactive-booking` tại commit `89c4fcd` làm tham chiếu; màu, chuyển động và chi tiết tiếp cận còn được tinh chỉnh.
2. **Khung và dữ liệu:** Router cho các tab/luồng đặt khám, Riverpod cho bản nháp, quy tắc giữ hoặc chọn lại dữ liệu. Cần kiểm tra nút Back của Android và quay lại sửa.
3. **Luồng cơ bản:** Sáu bước đặt khám, ngày/giờ/tiền tiếng Việt, xem lại lịch và trạng thái thanh toán giả lập theo PRD. Thẻ ngày dễ bấm là mặc định; lịch tháng chỉ bổ sung khi có nhu cầu.
4. **Hoàn thiện trải nghiệm:** Animation ngắn, loading skeleton, SVG, focus, đọc màn hình và cỡ chữ lớn. Không dùng animation để thay thông báo thanh toán; không tự giới hạn cỡ chữ theo prototype.

Mỗi đợt cần kiểm tra độc lập trước khi mở rộng. Các thư viện được cài sẵn không có nghĩa là mọi tính năng hoặc API của chúng đã được tích hợp và thử nghiệm. Font đã đóng gói; chưa tải illustration, chưa tạo giao dịch hoặc gọi AI thật. Các quyết định ngoài bố cục vẫn cần được đánh giá khi triển khai.

## Kiểm tra tại thời điểm cài package (trước bước 1)

- Dependency resolver tải thành công cả 9 package với phiên bản trong bảng.
- `flutter analyze`: Không phát hiện vấn đề.
- `flutter test`: Test mẫu pass (1 test).
- `flutter build apk --debug`: Thành công trên app starter hiện có.
- Build tự cài bổ sung Android SDK Platform 35 và CMake 3.22.1 vào `.devtools/android-sdk`; các thành phần này được gỡ cùng bộ công cụ dự án.
- Chưa kiểm tra các API package trong màn hình nghiệp vụ, chưa chạy trên điện thoại và chưa áp dụng giao diện prototype. Các bước này thực hiện theo từng đợt triển khai.

## Nguồn package đã tra cứu

Thông tin package do nhà phát hành công bố tại pub.dev, đã tra cứu ngày 2026-10-14:
[google_fonts](https://pub.dev/packages/google_fonts), [lucide_icons_flutter](https://pub.dev/packages/lucide_icons_flutter), [flutter_animate](https://pub.dev/packages/flutter_animate), [skeletonizer](https://pub.dev/packages/skeletonizer), [flutter_svg](https://pub.dev/packages/flutter_svg), [intl](https://pub.dev/packages/intl), [table_calendar](https://pub.dev/packages/table_calendar), [go_router](https://pub.dev/packages/go_router), [flutter_riverpod](https://pub.dev/packages/flutter_riverpod).

## Cập nhật bước 3

Đã triển khai luồng đặt lịch cơ bản, bản nháp Riverpod, catalog/repository mô phỏng, kiểm tra lựa chọn phụ thuộc, giờ khám và thanh toán giả lập. `intl` định dạng tiền/ngày; thẻ ngày vẫn là mặc định. Xem [bước 3](flutter_app/BOOKING.md). Footer bước trước giữ nguyên. Chưa tích hợp Smart Scheduling hoặc backend; các thư viện hiệu ứng bổ sung tiếp tục triển khai khi cần.

## Cập nhật bước 4

Đã tích hợp flutter_animate cho hiệu ứng vào bước và skeletonizer cho tải giờ khám; cả hai tôn trọng chế độ giảm chuyển động. Bổ sung kiểm tra chữ lớn, semantics, bàn phím và phản hồi lỗi. Xem [UI/UX bước 4](flutter_app/UI-UX.md). Không thêm SVG khi chưa có nhu cầu nội dung hoặc asset được duyệt. Footer và phạm vi nghiệp vụ bước 3 giữ nguyên.

## Cập nhật liên kết hai máy

Thêm [qr_flutter](https://pub.dev/packages/qr_flutter) 4.1.0 để vẽ mã QR liên kết trên máy chủ hồ sơ. Máy nhận quét mã bằng máy quét có sẵn từ bước 6, nên không thêm thư viện quét. Xem [Liên kết hai máy](flutter_app/LIEN-KET-HAI-MAY.md).
