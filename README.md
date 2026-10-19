# MedicApp — Cải thiện trải nghiệm MyVinmec

**Chủ dự án:** Nguyễn Mạnh Tú.

Kho bài tập nghiên cứu trải nghiệm người dùng và prototype Flutter nhằm cải thiện một khoảnh khắc trong hành trình sử dụng MyVinmec.

**Trạng thái (19/10/2026):** Đã có app người bệnh Flutter Android (đặt lịch, Smart Scheduling, hồ sơ gia đình từ QR CCCD, nhắc khám, đơn thuốc, nhắc và chuông thuốc, bản đồ cơ sở, liên kết hai máy), backend Node local và web bác sĩ Flutter Web (bước 13–18). Tất cả chạy với dữ liệu minh họa. App đã cài trên OPPO A77s; chủ dự án báo đã thử xong luồng đặt lịch cơ bản. Đã dùng thử MyVinmec và phỏng vấn 4 người (P1–P4); need statement, journey map và coach plan đã duyệt; phân tích insight và sổ rủi ro đang chờ duyệt. Đặt lịch thông minh và tóm tắt trước khám đã chạy với AI thật. Chưa có log thử prototype với người dùng. Xem [tổng quan prototype](05-prototype/README.md).

**Phạm vi bản bàn giao Git hiện tại:** Source app Flutter, web bác sĩ, backend, package `medic_core`, font có giấy phép, tests/ảnh chuẩn, tài liệu và script cài/kích hoạt/gỡ bộ công cụ portable. Không bao gồm SDK/cache, APK, API key hoặc dữ liệu sức khỏe thật. Xem [hướng dẫn chạy app](05-prototype/flutter_app/README.md) và [backend](05-prototype/backend/README.md).

## Khoảnh khắc đã chọn

Khoảnh khắc ưu tiên: **người dùng, trọng tâm nhóm 50–60+, tự đặt một lượt khám ngoại trú và hiểu rõ kết quả đặt lịch**. Bối cảnh là khó khăn với nhiều bước và chọn chuyên khoa, theo tóm tắt phỏng vấn do chủ dự án cung cấp; được củng cố bằng [log phỏng vấn P1–P4](01-phong-van/logs/README.md) và [ghi chép dùng thử MyVinmec](01-phong-van/ghi-chep-dung-thu.md).

Xem [PRD Smart Scheduling](05-prototype/prd-smart-scheduling.md) và [ba best practice đề xuất](04-best-practice/README.md). Ưu tiên duyệt luồng đặt khám cơ bản trước; gợi ý khoa và giờ là nhánh hỗ trợ có fallback.

## Mục lục

| Hạng mục | Nội dung |
| --- | --- |
| [01-phong-van](01-phong-van/) | Ghi chép dùng thử, interview guide, log ẩn danh, phân tích insight |
| [02-journey-map](02-journey-map/) | Journey map/workflow và điểm đau |
| [03-need-statement](03-need-statement/) | Need statement và bằng chứng |
| [04-best-practice](04-best-practice/) | Ba best practice, nguồn và bài học cho Vinmec |
| [05-prototype](05-prototype/) | App Flutter, backend, web bác sĩ, PRD, prompt log, log thử và lịch sử chỉnh sửa |
| [06-rui-ro-dao-duc](06-rui-ro-dao-duc/) | Rủi ro, giảm thiểu và luồng chuyển tuyến khẩn cấp |
| [07-coach-plan](07-coach-plan/) | Kế hoạch coach một trang |
| [slides.pdf](slides.pdf) | Deck 10 slide |

## Công cụ AI hỗ trợ

Code, tài liệu kỹ thuật và tests được viết với Codex (bước 1–4) và Claude Code (Smart Scheduling và các bước sau). Từng lần sử dụng, prompt và cách kiểm tra được ghi trong [prompt log](05-prototype/prompts/README.md).

## Nguyên tắc lưu trữ

- Chỉ commit dữ liệu đã ẩn danh (P1, P2, P3…). Không commit tên thật, liên hệ, hồ sơ sức khỏe, token hoặc khóa ký ứng dụng.
- SDK/cache đặt trong `.devtools/` và `.devcache/`, không đẩy lên Git.
- Flutter project nằm trong [05-prototype/flutter_app](05-prototype/flutter_app/). Xem [hướng dẫn môi trường, đăng nhập gh và gỡ cài đặt](scripts/README.md).
- Trước khi nộp: thay nội dung mẫu bằng dữ liệu đã kiểm chứng, hoàn thiện prototype, xuất `slides.pdf` tối đa 10 slide và kiểm tra các liên kết.
