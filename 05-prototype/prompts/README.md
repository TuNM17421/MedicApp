# Prompt log

## AI-001 — Khởi tạo cấu trúc bàn giao

- Yêu cầu: “Check và dựng lại structure project cho tôi xem”, dựa trên bảng cấu trúc bàn giao người dùng cung cấp.
- Đầu vào: Tên thư mục và nội dung cần nộp cho bài nghiên cứu MyVinmec.
- Đầu ra: Khung thư mục, README, biểu mẫu, dàn ý slide và `.gitignore`.
- Công cụ: Codex.
- Kiểm tra: Kiểm tra cấu trúc và liên kết nội bộ; chưa kiểm chứng nội dung nghiên cứu vì chưa có dữ liệu.

## AI-002 — Thiết lập Flutter Android

- Ngày: 2026-10-14.
- Prompt: “Tiếp theo cài môi trường Flutter cho Android theo cách dễ gỡ như đã đề xuất, rồi khởi tạo app trong 05-prototype/flutter_app giúp tôi. Kiểm tra xem terminal đã có gh chưa nếu chưa có thì cho phép install về và tôi sẽ login”.
- Công cụ: Codex, PowerShell, Flutter CLI.
- Đầu ra: Script môi trường portable trong `scripts/`, manifest phiên bản/checksum, Flutter Android starter sinh từ template chính thức, tài liệu chạy và gỡ môi trường.
- Phạm vi: Khởi tạo công cụ và app mẫu; chưa tạo dữ liệu nghiên cứu hoặc tính năng y tế. Người dùng tự đăng nhập GitHub.
- Kiểm chứng: Xem [kết quả thiết lập](../../scripts/verification.md).

## AI-003 — PRD Smart Scheduling, chưa code

- Ngày: 2026-10-14.
- Yêu cầu tóm tắt: Dựa trên khó khăn đặt khám của người 50–60+ do chủ dự án cung cấp, viết PRD cho một app đặt khám tối giản theo hướng MyTherapy, luồng cơ bản tham chiếu MyVinmec/Bạch Mai Care; ghi nhận best practice. Luồng cơ bản là nền và fallback cho gợi ý khoa từ triệu chứng/giọng nói và gợi ý giờ ít chờ. Chủ dự án sẽ dùng agent khác dựng prototype để duyệt trước khi áp dụng vào Flutter.
- Đầu vào: Hội thoại và nguồn công khai S1–S4 trong `04-best-practice/README.md`; không có log phỏng vấn gốc hoặc dữ liệu bệnh viện.
- Đầu ra: `05-prototype/prd-smart-scheduling.md`, cập nhật best practice, README và prompt log.
- Công cụ: Codex và tìm kiếm web; không sửa code Flutter, không triển khai AI/backend, không commit/push.
- Điều chỉnh cần duyệt: Dùng ngôn ngữ gợi ý có giới hạn thay cho cam kết đúng khoa/giờ vắng nhất; các ước tính và giao dịch chỉ mô phỏng khi chưa có dữ liệu vận hành. Quy tắc BHYT và luồng khẩn cần đơn vị chuyên môn xác nhận trước triển khai thật.
- Kiểm chứng: Mở nguồn chính thức, phân biệt thông tin công bố với suy luận thiết kế; kiểm tra liên kết Markdown nội bộ. Chưa kiểm thử app tham chiếu, hiệu quả với người dùng hoặc tính phù hợp lâm sàng.

## Mẫu cho lần sử dụng tiếp theo

- Mã, ngày, người sử dụng, công cụ/model nếu biết.
- Prompt nguyên văn đã loại bỏ dữ liệu nhạy cảm và đầu vào tham chiếu.
- File/kết quả được tạo.
- Phần chấp nhận, chỉnh sửa hoặc loại bỏ; người kiểm tra và cách kiểm chứng.
