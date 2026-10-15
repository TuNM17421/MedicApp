# Backend Smart Scheduling — chuẩn bị cấu hình

**PRD triển khai hiện hành:** [Smart Scheduling](../prd-smart-scheduling-implementation.md), ngày 2026-10-15. Hỏi đáp mặc định `gpt-6-luna` / reasoning `low` để tiết kiệm khi test; STT giữ `gpt-live-transcribe`. Không tự fallback sang model đắt.

**Cập nhật v2:** [Luồng hội thoại streaming](../smart-scheduling-conversation.md) thay thế luồng chép file. Mẫu cấu hình dùng `gpt-live-transcribe`; backend cần thêm WebSocket relay và điều phối nhiều lượt. Chưa có các thành phần này chạy được.

Thư mục này hiện **chỉ có mẫu cấu hình**, chưa có server, dependency, endpoint hoặc kết nối OpenAI hoạt động. App trên điện thoại vẫn là bản đặt lịch cơ bản, chưa đọc cấu hình này. Xem [nghiên cứu và thiết kế tích hợp](../smart-scheduling-research.md).

Chỗ điền key khi triển khai backend là file `.env` cục bộ trong thư mục này. Tạo từ mẫu:

```powershell
# Chạy từ C:\Coding\MedicApp, chỉ sao chép khi chưa có file .env.
if (-not (Test-Path .\05-prototype\backend\.env)) {
    Copy-Item .\05-prototype\backend\.env.example .\05-prototype\backend\.env
}
```

Mở `.env` bằng editor và điền `OPENAI_API_KEY` trên máy của bạn, không gửi key vào chat. `.env` đã được quy tắc `.gitignore` ở gốc loại khỏi Git; `.env.example` chỉ chứa tên biến và giá trị không bí mật.

Backend tương lai phải nạp file này một cách tường minh, kiểm tra biến bắt buộc khi khởi động, che key trong log và chỉ báo trạng thái cấu hình. Thay key/model cần khởi động lại backend; không cần đóng gói key vào APK. Đổi model vẫn cần kiểm tra chất lượng và quyền truy cập trước khi dùng.

Khi backend và app đã được triển khai, điện thoại Android đang nối USB sẽ truy cập server qua `adb reverse tcp:8080 tcp:8080`. App chỉ giữ `API_BASE_URL=http://127.0.0.1:8080` trong cấu hình debug. URL không phải bí mật. Hiện chưa có server hoặc cấu hình Flutter tương ứng để chạy các API đó.

Các model trong mẫu là lựa chọn nghiên cứu ngày 2026-10-14; chưa gọi API, chưa kiểm tra quyền model của tài khoản và chưa có dữ liệu đánh giá nhận giọng tiếng Việt. Giới hạn 60 giây/5 MiB là đề xuất của ứng dụng, chưa được thực thi.
