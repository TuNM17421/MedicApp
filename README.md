# MedicApp — Cải thiện trải nghiệm MyVinmec

Kho bài tập nghiên cứu trải nghiệm người dùng và prototype Flutter nhằm cải thiện một khoảnh khắc trong hành trình sử dụng MyVinmec.

**Trạng thái:** Đã dựng khung tài liệu, cài bộ công cụ Android portable và khởi tạo Flutter app mẫu. Đã nghiên cứu nguồn công khai và soạn PRD đặt khám, chờ duyệt prototype. Chưa có log phỏng vấn ẩn danh hoặc kết quả thử nghiệm được đưa vào repo; chưa triển khai luồng nghiệp vụ bằng Flutter.

**Phạm vi bản bàn giao Git hiện tại:** Tài liệu, `.gitignore` và manifest phiên bản công cụ. Source Flutter và script cài/kích hoạt/gỡ môi trường hiện có trên máy phát triển, chưa thuộc bản đẩy tài liệu này. Các lệnh chạy trong tài liệu môi trường cần các script cục bộ đó.

## Khoảnh khắc đã chọn

Khoảnh khắc ưu tiên do chủ dự án chọn: **người dùng, trọng tâm nhóm 50–60+, tự đặt một lượt khám ngoại trú và hiểu rõ kết quả đặt lịch**. Bối cảnh là khó khăn với nhiều bước và chọn chuyên khoa, theo tóm tắt phỏng vấn do chủ dự án cung cấp; cần bổ sung log ẩn danh để kiểm tra bằng chứng.

Xem [PRD Smart Scheduling](05-prototype/prd-smart-scheduling.md) và [ba best practice đề xuất](04-best-practice/README.md). Ưu tiên duyệt luồng đặt khám cơ bản trước; gợi ý khoa và giờ là nhánh hỗ trợ có fallback.

## Mục lục

| Hạng mục | Nội dung |
| --- | --- |
| [01-phong-van](01-phong-van/) | Ghi chép dùng thử, interview guide, log ẩn danh, phân tích insight |
| [02-journey-map](02-journey-map/) | Journey map/workflow và điểm đau |
| [03-need-statement](03-need-statement/) | Need statement và bằng chứng |
| [04-best-practice](04-best-practice/) | Ba best practice, nguồn và bài học cho Vinmec |
| [05-prototype](05-prototype/) | Source Flutter, prompt, log thử và lịch sử chỉnh sửa |
| [06-rui-ro-dao-duc](06-rui-ro-dao-duc/) | Rủi ro, giảm thiểu và luồng chuyển tuyến khẩn cấp |
| [07-coach-plan](07-coach-plan/) | Kế hoạch coach một trang |
| slides.pdf | Deck tối đa 10 slide — chưa xuất; xem [dàn ý](slides-outline.md) |

## Phần do AI tạo

- AI đã tạo cấu trúc thư mục, README, biểu mẫu nghiên cứu, dàn ý slide và cấu hình bỏ qua file trong Git.
- Các biểu mẫu là khung để điền, không phải kết quả nghiên cứu hoặc bằng chứng thực tế.
- AI đã viết script cài/kích hoạt/gỡ môi trường và chạy `flutter create` để sinh app mẫu cùng test từ template chính thức của Flutter. Chưa có luồng nghiệp vụ tùy chỉnh.
- AI tổng hợp nguồn công khai trong phần best practice và soạn PRD, bao gồm luồng, đề xuất thị giác, trạng thái lỗi và tiêu chí duyệt. Các đề xuất chưa phải kết quả kiểm thử người dùng hoặc xác nhận chuyên môn.
- Chưa có log phỏng vấn hoặc kết quả dùng thử thực tế được đưa vào repo. Tóm tắt khó khăn do chủ dự án cung cấp được ghi riêng với nghiên cứu nguồn công khai.
- Khi bổ sung nội dung, ghi tác giả/người kiểm tra và phần AI hỗ trợ trong từng tài liệu; lưu prompt tại [05-prototype/prompts](05-prototype/prompts/).

## Nguyên tắc lưu trữ

- Chỉ commit dữ liệu đã ẩn danh (P1, P2, P3…). Không commit tên thật, liên hệ, hồ sơ sức khỏe, token hoặc khóa ký ứng dụng.
- SDK/cache đặt trong `.devtools/` và `.devcache/`, không đẩy lên Git.
- Flutter project nằm trong [05-prototype/flutter_app](05-prototype/flutter_app/). Xem [hướng dẫn môi trường, đăng nhập gh và gỡ cài đặt](scripts/README.md).
- Trước khi nộp: thay nội dung mẫu bằng dữ liệu đã kiểm chứng, hoàn thiện prototype, xuất `slides.pdf` tối đa 10 slide và kiểm tra các liên kết.
