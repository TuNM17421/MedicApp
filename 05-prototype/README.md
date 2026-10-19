# 05 — Prototype Flutter

**Trạng thái (19/10/2026):** Bố cục prototype đã được chủ dự án duyệt. Đã có app người bệnh Flutter Android, backend Node local và web bác sĩ Flutter Web, tất cả chạy với dữ liệu minh họa. App đã cài trên OPPO A77s; chủ dự án báo đã thử xong luồng đặt lịch cơ bản. Chưa gọi OpenAI bằng key thật, chưa có nhà cung cấp SMS, chưa chạy thử với phòng khám hay người dùng thật, và chưa có log thử trong [test-logs/](test-logs/).

## Thành phần

| Thư mục | Nội dung |
| --- | --- |
| [flutter_app/](flutter_app/README.md) | App người bệnh: đặt lịch, Smart Scheduling, hồ sơ gia đình, nhắc khám, đơn thuốc, nhắc và chuông thuốc, bản đồ cơ sở, liên kết hai máy |
| [backend/](backend/README.md) | Server Node local: Smart Scheduling, API phòng khám ([CLINIC-API.md](backend/CLINIC-API.md)), API gia đình ([FAMILY-API.md](backend/FAMILY-API.md)) |
| [doctor_web/](doctor_web/README.md) | Web bác sĩ: hàng chờ, tóm tắt trước khám, tuân thủ thuốc, kê đơn, gửi kết quả, quản trị |
| [packages/medic_core/](packages/medic_core/README.md) | Package Dart dùng chung cho app và web: đơn thuốc, nhật ký liều, tuân thủ 30 ngày |
| [docs/](docs/) | [Kế hoạch chạy thử](docs/ke-hoach-chay-thu.md) và [hồ sơ đánh giá tác động dữ liệu](docs/danh-gia-tac-dong-du-lieu.md), bản nháp |
| [prompts/](prompts/README.md) | Prompt log AI-001 trở đi và [prompt dựng prototype vòng 1](prompts/prototype-agent-brief.md) |
| [test-logs/](test-logs/) | Log thử với 2–3 người, đã ẩn danh. Chưa có |
| [changes.md](changes.md) | Thay đổi sau thử nghiệm. Chưa có |

## Tài liệu theo tính năng

| Tính năng | Tài liệu |
| --- | --- |
| Nền giao diện, điều hướng, UI/UX (bước 1, 2, 4) | [DESIGN-SYSTEM](flutter_app/DESIGN-SYSTEM.md), [NAVIGATION](flutter_app/NAVIGATION.md), [UI-UX](flutter_app/UI-UX.md), [LAM-DEP-UI](flutter_app/LAM-DEP-UI.md), [thư viện](dependency-plan.md) |
| Đặt lịch cơ bản (bước 3) | [BOOKING](flutter_app/BOOKING.md) |
| Smart Scheduling | [PRD gốc](prd-smart-scheduling.md), [nghiên cứu](smart-scheduling-research.md), [hội thoại v2](smart-scheduling-conversation.md), [PRD triển khai](prd-smart-scheduling-implementation.md), [màn trong app](flutter_app/SMART-SCHEDULING.md) |
| Đăng ký và hồ sơ từ QR CCCD | [AUTH-CCCD](flutter_app/AUTH-CCCD.md) |
| Lưu ý trước khám, nhắc khám | [LUU-Y-TRUOC-KHAM](flutter_app/LUU-Y-TRUOC-KHAM.md), [THONG-BAO-NHAC-KHAM](flutter_app/THONG-BAO-NHAC-KHAM.md) |
| Lưu dữ liệu trên máy | [LUU-TRU-DU-LIEU](flutter_app/LUU-TRU-DU-LIEU.md) |
| Kết quả khám, đơn thuốc, nhắc thuốc | [DON-THUOC](flutter_app/DON-THUOC.md), [NHAC-THUOC](flutter_app/NHAC-THUOC.md) |
| Liên kết hai máy | [LIEN-KET-HAI-MAY](flutter_app/LIEN-KET-HAI-MAY.md) |
| Web bác sĩ (bước 13–18) | [WEB-BAC-SI-NEN](flutter_app/WEB-BAC-SI-NEN.md), [doctor_web](doctor_web/README.md), [backend](backend/README.md#web-bác-sĩ) |

## Nguyên tắc

Dữ liệu bệnh viện, lịch, thanh toán và người bệnh đều là dữ liệu minh họa; ghi rõ thao tác nào chưa kết nối hệ thống thật. Need statement chính thức cần được đối chiếu bằng chứng nghiên cứu trong [01-phong-van](../01-phong-van/). Xem [hướng dẫn chạy app](flutter_app/README.md) và [cài/gỡ môi trường](../scripts/README.md). Commit `pubspec.lock`; không commit SDK, file build, `.env` hoặc bí mật.
