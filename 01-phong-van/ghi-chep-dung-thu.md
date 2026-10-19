# Ghi chép dùng thử MyVinmec

**Trạng thái:** Đã dùng thử. Ghi chép do chủ dự án thực hiện; AI dựng lại thành bảng, giữ nguyên nội dung quan sát.

- **Ngày:** 19/10/2026. **Người thực hiện:** chủ dự án.
- **Nền tảng:** App MyVinmec trên điện thoại Android và website Vinmec (form "Đặt lịch hẹn"). Phiên bản app: chưa ghi.
- **Tình huống:** Đặt khám xương khớp cho bản thân.
- **Điểm bắt đầu/kết thúc:** Từ tab Đặt lịch đến màn "Thông tin đặt hẹn" trước khi bấm "Xác nhận lịch hẹn". Không gửi lịch thật vì đây là hệ thống thật.
- Ngoài đặt lịch, đã xem thêm các tính năng đơn thuốc, nhắc uống thuốc, thông tin bác sĩ, dịch vụ y tế, sàng lọc đột quỵ, cộng đồng hỏi đáp và chatbot.

## Đặt lịch khám

| Bước | Thao tác | Phản hồi quan sát được | Khó khăn | Mã bằng chứng |
| --- | --- | --- | --- | --- |
| 1 | Mở Lịch hẹn | Trạng thái trống "Hiện tại bạn chưa có lịch hẹn nào", nút Đặt hẹn, hướng dẫn kiểm tra hồ sơ y tế và số hotline | — | DT-O01 |
| 2 | Chọn cách đặt | Ba cách: theo bác sĩ, theo chuyên khoa, theo triệu chứng | Người dùng phải tự biết nên chọn cách nào | DT-O02 |
| 3 | Chọn chuyên khoa và bác sĩ, rồi chọn ngày | Với 3 bác sĩ đầu, cả 3 ngày tới và một ngày cách 11 ngày đều báo "Bác sĩ không có lịch trống trong 3 ngày… Vui lòng chọn ngày khác" | Phải thử lần lượt từng bác sĩ, từng ngày; đến bác sĩ thứ 4 mới có lịch | DT-O03 |
| 4 | Chờ kiểm tra lịch | Mỗi lần kiểm tra lịch bác sĩ mất hơn 4 giây | Thử nhiều lần nên tổng thời gian chờ dài | DT-O04 |
| 5 | Xem "Thông tin đặt hẹn" | Hình thức, khách hàng, lý do khám, bác sĩ, thời gian, địa điểm, chuyên khoa, phí dự kiến 690.000đ | Chỉ có giờ bắt đầu, không có giờ kết thúc; không có chỗ gửi câu hỏi hay tình trạng bệnh cho bác sĩ trước khám | DT-O05 |
| 6 | Đặt trên website | Form điền: nơi khám, chuyên khoa, bác sĩ, ngày, buổi, thông tin khách hàng; tổng đài viên gọi lại xác nhận | Không có gợi ý hay hướng dẫn chọn; phần lớn trang dẫn tới đường dây nóng | DT-O06 |

## Các tính năng khác

| Tính năng | Quan sát | Mã bằng chứng |
| --- | --- | --- |
| Đơn thuốc, nhắc uống thuốc | Cần kết nối hồ sơ sức khỏe tại Vinmec hoặc chụp ảnh đơn Vinmec; không có đơn mẫu nên không thử được | DT-O07 |
| Thông tin bác sĩ | Công khai chức vụ, nơi công tác, kinh nghiệm, giải thưởng, nghiên cứu, chuyên khoa. Mục "Giải thưởng và ghi nhận" của một bác sĩ hiện lỗi kỹ thuật "sequence item 0: expected str instance, NoneType found" | DT-O08 |
| Dịch vụ y tế | Danh mục gói dịch vụ, mỗi gói có "Nhận tư vấn" để nhân viên liên hệ | DT-O09 |
| Sàng lọc đột quỵ | 3 câu Có/Không và giờ khởi phát; chọn Có ở bất kỳ câu nào đều kết luận có dấu hiệu đột quỵ và hiện nút "Gọi cấp cứu" | DT-O10 |
| Cộng đồng hỏi đáp bác sĩ | Danh sách câu hỏi thường gặp để đọc trước, có ô tìm kiếm | DT-O11 |
| Chatbot "Trợ lý sức khỏe AI MIA" | Chỉ trả lời câu hỏi y tế; hỗ trợ kiểm tra triệu chứng, phân tích dinh dưỡng, đặt lịch khám, liên kết ứng dụng. Câu trả lời dài, trình bày khó nhìn | DT-O12 |

## Suy luận của người dùng thử

Đây là đề xuất của chủ dự án, không phải quan sát:

- Nên có gợi ý chuyên khoa từ triệu chứng người bệnh nêu, rồi tìm bác sĩ còn lịch gần nhất với ngày người bệnh muốn, thay vì bắt thử từng bác sĩ (từ DT-O03, DT-O04).
- Nên cho gửi câu hỏi hoặc mô tả tình trạng cho bác sĩ trước khi khám (từ DT-O05).

## Ảnh chụp màn hình

Chủ dự án đã chụp 13 ảnh tương ứng với các mã trên (`dat-lich-hen-1/2/3`, `xac-nhan-dat-lich-hen`, `dat-lich-hen-website`, `don-thuoc`, `nhac-lich-uong-thuoc`, `thong-tin-bac-si`, `thong-tin-bac-si-website`, `dich-vu-y-te`, `sang-loc-dot-quy`, `cong-dong-hoi-bac-si`, `hoi-dap-chat-bot`). Ảnh sẽ được thêm vào `anh/` sau khi kiểm tra đã che hết thông tin cá nhân.
