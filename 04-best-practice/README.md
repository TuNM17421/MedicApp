# 04 — Ba best practice

**Trạng thái:** Nghiên cứu tài liệu công khai và đề xuất áp dụng, ngày 2026-10-14. Chưa kiểm thử trực tiếp các app hoặc chứng minh hiệu quả với nhóm người dùng mục tiêu. AI tổng hợp nguồn và viết phần suy luận; người phụ trách nghiên cứu cần duyệt.

## Bối cảnh từ người dùng cung cấp

Theo tóm tắt phỏng vấn do chủ dự án cung cấp: người trên 50–60 tuổi gặp khó khăn với việc đặt khám nhiều bước, thường nhờ con cái hoặc nhân viên bệnh viện thao tác hộ. Đây là thông tin đầu vào, chưa có log ẩn danh, số người tham gia hoặc trích dẫn để kiểm tra; không trình bày như kết quả do AI tự thu thập.

## Ba best practice đề xuất

### BP-01 — Giao diện tập trung vào tác vụ, trạng thái dễ nhận biết

- **Tham chiếu:** MyTherapy (S1) công bố các tác vụ nhắc thuốc và ghi nhận đã dùng/bỏ qua.
- **Hướng thiết kế do chủ dự án chọn:** Giao diện tối giản theo tinh thần MyTherapy. Chưa có bộ screenshot cụ thể được duyệt để khẳng định các thuộc tính thị giác của app hiện tại.
- **Suy luận áp dụng:** Mỗi màn hình đặt khám có một quyết định chính, chữ lớn, nhãn rõ và một nút tiếp tục nổi bật. Hiển thị phần đã chọn để người dùng không phải nhớ. Không sao chép màn hình quản lý thuốc sang đặt khám.
- **Cần kiểm chứng:** Người dùng 50–60+ hiểu bước tiếp theo, tự sửa lựa chọn và hoàn thành tác vụ khi tăng cỡ chữ; không mặc định mọi người lớn tuổi có cùng nhu cầu.

### BP-02 — Luồng đặt khám có cấu trúc, hỗ trợ người thân và minh bạch tiến trình

- **Tham chiếu:** MyVinmec (S2) mô tả đặt lịch cho bản thân/người thân và QR check-in. Bạch Mai Care (S3) mô tả đặt lịch theo khoa/khung giờ và tiến độ chỉ định trong ngày khám.
- **Luồng do chủ dự án yêu cầu:** Hình thức khám → Người khám → Nơi khám/khoa → Ngày giờ → Kiểm tra → Thanh toán. Đây là yêu cầu cho sản phẩm mới, chưa phải bản sao đã xác minh từng màn hình của hai app.
- **Suy luận áp dụng:** Dùng một hồ sơ đặt khám xuyên suốt; cho phép quay lại chỉnh sửa; thông báo rõ lựa chọn nào cần chọn lại khi đổi cơ sở hoặc hình thức. Tách trạng thái giữ giờ, thanh toán và xác nhận lịch để không báo thành công sớm.
- **Cần kiểm chứng:** Giảm nhầm người khám và nhầm khung giờ. Tiến độ khám của Bạch Mai là tham chiếu về sự minh bạch, không phải bằng chứng bệnh viện đang công bố dự báo thời gian chờ.

### BP-03 — Hỗ trợ có giới hạn rõ ràng và có đường chuyển tiếp

- **Tham chiếu:** Ada (S4) mô tả việc dùng triệu chứng/thông tin sức khỏe để gợi ý nguyên nhân có thể liên quan và bước tiếp theo; nêu giới hạn về chẩn đoán và hỗ trợ chuyên môn.
- **Suy luận áp dụng:** Gợi ý chuyên khoa cần giải thích ngắn, người dùng xác nhận và có nút tự chọn khoa. Khi thiếu thông tin, AI lỗi hoặc không nhận được giọng nói, chuyển về luồng cơ bản và giữ dữ liệu hợp lệ. Nếu gặp tình huống có thể khẩn cấp, ưu tiên luồng trợ giúp đã được chuyên môn duyệt, không đưa về đặt lịch thường.
- **Giới hạn:** Không suy ra Ada cung cấp chức năng đặt lịch bệnh viện, bảo đảm chọn đúng khoa hoặc dự báo giờ vắng. Tối ưu giờ khám là giả thuyết sản phẩm mới, cần dữ liệu vận hành và kiểm định riêng.

## Quyết định đưa vào prototype

| Nhu cầu / ý tưởng | Quyết định hiện tại | Phần cần xác minh |
| --- | --- | --- |
| Đặt lịch cơ bản ít khó khăn hơn | Ưu tiên số một, độc lập với AI | Dùng thử với người 50–60+ và người hỗ trợ |
| Nhập/nói triệu chứng để gợi ý khoa | Nhánh minh họa, người dùng xác nhận | Tính phù hợp lâm sàng, giọng nói tiếng Việt, giới hạn của mô hình |
| Gợi ý bác sĩ | Lọc theo khoa, cơ sở, hình thức và lịch còn trống | Danh mục và lịch bác sĩ thật; không tuyên bố bác sĩ tốt nhất |
| Khung giờ ít chờ | Chỉ mô phỏng; dùng nhãn “dự kiến ít chờ” khi có dữ liệu phù hợp | Lịch bác sĩ, tải bệnh nhân, thời gian xử lý, chất lượng dự báo |
| BHYT / tự chi trả | Cho chọn ngay đầu luồng theo yêu cầu | Cơ sở/khoa hỗ trợ, điều kiện và chi phí do bệnh viện xác nhận |

Xem [PRD Smart Scheduling](../05-prototype/prd-smart-scheduling.md) để có luồng màn hình, trạng thái lỗi và tiêu chí duyệt prototype.

## Danh mục nguồn

Tất cả truy cập ngày **2026-10-14**. Các mô tả trên là thông tin nhà cung cấp công bố; chưa phải đánh giá độc lập.

| Mã | Tên tài liệu / tổ chức | Link | Phạm vi dùng làm bằng chứng |
| --- | --- | --- | --- |
| S1 | MyTherapy — trang sản phẩm / smartpatient | [Website](https://www.mytherapyapp.com/) | Tác vụ nhắc thuốc và ghi nhận trạng thái |
| S2 | MyVinmec – Trợ lý sức khỏe / Vinmec | [Google Play](https://play.google.com/store/apps/details?hl=vi&id=com.vinmec.onevinmec) | Đặt lịch gia đình, hồ sơ, QR check-in |
| S3 | Bạch Mai Care: Làm chủ lộ trình khám bệnh / Bệnh viện Bạch Mai, 21/04/2026 | [Bài hướng dẫn](https://bachmai.gov.vn/bai-viet/bach-mai-care-ho-so-suc-khoe-lam-chu-lo-trinh-kham-benh-xoa-bo-noi-lo-cho-doi?id=d096f35e-d5d1-4147-b8c5-32b278a36d35) | Khoa/giờ khám, kiosk và tiến độ chỉ định |
| S4 | Does Ada act as a medical device? / Ada | [Phạm vi và giới hạn](https://ada.com/help/what-degree-of-liability-does-ada-accept/) | Hỗ trợ triệu chứng, bước tiếp theo và giới hạn sử dụng |
