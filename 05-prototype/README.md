# 05 — Prototype Flutter

- [Nghiên cứu Smart Scheduling + STT](smart-scheduling-research.md): Chọn model, backend giữ key, test qua USB, giới hạn dữ liệu và kế hoạch triển khai. [Mẫu cấu hình backend](backend/.env.example) đã có; server và nhánh AI chưa được triển khai.

- [Hoàn thiện UI/UX bước 4](flutter_app/UI-UX.md): Animation nhẹ, skeleton khi tải giờ, giảm chuyển động, cỡ chữ lớn và phản hồi dễ thấy. Footer giữ nguyên, chưa Smart Scheduling.

**Trạng thái:** Bố cục prototype đã được chủ dự án duyệt. Đã có nền giao diện, shell điều hướng và luồng đặt lịch cơ bản bước 3 với thanh toán giả lập; chưa làm Smart Scheduling.

- [Thư viện và thứ tự triển khai](dependency-plan.md): Đã cài 9 package UI/UX; tích hợp dần theo từng đợt.
- [Nền giao diện bước 1](flutter_app/DESIGN-SYSTEM.md): Theme, font offline, icon, widget và kết quả kiểm tra.
- [Khung app bước 2](flutter_app/NAVIGATION.md): go_router, các tab, Back và Riverpod cho hồ sơ/thông báo.
- [prd-smart-scheduling.md](prd-smart-scheduling.md): PRD đặt khám cơ bản và Smart Scheduling, chờ duyệt prototype; không sửa code Flutter ở bước này.
- [Prompt dựng prototype vòng 1](prompts/prototype-agent-brief.md): Có thể sao chép sang agent khác; ưu tiên luồng cơ bản P0, hoãn nhánh AI, giữ nguyên Flutter.
- [flutter_app/](flutter_app/): Tài liệu app mẫu; source Android và test sinh bởi `flutter create` đang có cục bộ, chưa được đẩy cùng bản tài liệu.
- [prompts/](prompts/): Prompt và thông tin kiểm tra đầu ra AI.
- [test-logs/](test-logs/): Log thử với 2–3 người, đã ẩn danh.
- [changes.md](changes.md): Những thay đổi sau thử nghiệm.

Trình tự hiện tại: đã triển khai nền giao diện và khung điều hướng/trạng thái; luồng đặt khám cơ bản đã chạy bằng dữ liệu giả định. Need statement chính thức cần được đối chiếu bằng chứng nghiên cứu. Dùng dữ liệu giả lập cho prototype; ghi rõ các thao tác chưa kết nối hệ thống bệnh viện.

Xem [hướng dẫn chạy app](flutter_app/README.md) và [cài/gỡ môi trường](../scripts/README.md). Commit `pubspec.lock` của ứng dụng; không commit SDK, file build hoặc bí mật.

- [Luồng đặt lịch bước 3](flutter_app/BOOKING.md): Chọn thông tin, sửa lựa chọn, thanh toán giả lập và lịch hẹn.

- [Smart Scheduling hội thoại streaming v2](smart-scheduling-conversation.md): Luồng Smart hiện hành, thay cho bước xác nhận transcript riêng của nghiên cứu v1.
