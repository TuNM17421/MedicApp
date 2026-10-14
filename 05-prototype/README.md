# 05 — Prototype Flutter

**Trạng thái:** Đã khởi tạo Flutter Android app mẫu bằng Flutter 3.47.7 / Dart 3.13.5. Chưa triển khai luồng nghiên cứu MyVinmec.

- [prd-smart-scheduling.md](prd-smart-scheduling.md): PRD đặt khám cơ bản và Smart Scheduling, chờ duyệt prototype; không sửa code Flutter ở bước này.
- [flutter_app/](flutter_app/): Tài liệu app mẫu; source Android và test sinh bởi `flutter create` đang có cục bộ, chưa được đẩy cùng bản tài liệu.
- [prompts/](prompts/): Prompt và thông tin kiểm tra đầu ra AI.
- [test-logs/](test-logs/): Log thử với 2–3 người, đã ẩn danh.
- [changes.md](changes.md): Những thay đổi sau thử nghiệm.

Trình tự tiếp theo: duyệt PRD → agent khác dựng prototype tương tác → chủ dự án duyệt → mới áp dụng thiết kế thành Flutter. Need statement chính thức cần được đối chiếu bằng chứng nghiên cứu. Dùng dữ liệu giả lập cho prototype; ghi rõ các thao tác chưa kết nối hệ thống bệnh viện.

Xem [hướng dẫn chạy app](flutter_app/README.md) và [cài/gỡ môi trường](../scripts/README.md). Commit `pubspec.lock` của ứng dụng; không commit SDK, file build hoặc bí mật.
