# 06 — Rủi ro an toàn và đạo đức

**Trạng thái:** Đang chờ duyệt (19/10/2026). Mức độ là đánh giá định tính của nhóm, chưa có chuyên gia y tế hoặc pháp lý rà soát. Người phụ trách: Nguyễn Mạnh Tú cho đến khi phân công khác.

## Sổ rủi ro

Mức: C = cao, TB = trung bình, T = thấp (mức độ tác hại / khả năng xảy ra).

| Mã | Tình huống | Tác hại có thể xảy ra | Mức | Cách giảm thiểu đã có | Cách kiểm chứng | Việc còn mở |
| --- | --- | --- | --- | --- | --- | --- |
| R01 | AI gợi ý sai chuyên khoa | Khám sai khoa, mất thời gian, chậm điều trị | TB/TB | Ghi "Chuyên khoa gợi ý — cần được cơ sở y tế xác nhận"; luôn có tự chọn và sửa đề xuất; chỉ dùng khoa trong catalog | Bộ câu thử có nhãn trong `backend/eval` | Cần người có chuyên môn gán nhãn bộ thử |
| R02 | Người bệnh mô tả dấu hiệu cấp cứu khi đặt lịch | Chậm cấp cứu nếu app vẫn đặt khám thường | C/T | Smart Scheduling dừng đặt lịch và gợi ý gọi 115 (xem mục dưới) | Kịch bản T10 trong PRD | Danh sách dấu hiệu chờ người có chuyên môn đề xuất và phân loại |
| R03 | Bỏ sót dấu hiệu cần chú ý trong câu trả lời trước khám | Bác sĩ không thấy cảnh báo | C/T | Dấu hiệu bắt bằng danh sách cụm từ, không nhờ AI; khung đỏ trích nguyên văn; mỗi câu tóm tắt dẫn về câu gốc | Test backend bước 17 | Danh sách cụm từ cần bác sĩ duyệt |
| R04 | Lộ dữ liệu sức khỏe trên điện thoại | Lộ thông tin nhạy cảm | C/T | Chỉ lưu sau khi đồng ý rõ ràng; file mã hóa AES-256-GCM, khóa trong Android Keystore; "Ngừng lưu và xóa khỏi máy" | `LUU-TRU-DU-LIEU.md` | — |
| R05 | Gửi dữ liệu sức khỏe ra dịch vụ AI nước ngoài | Chuyển dữ liệu nhạy cảm ra nước ngoài khi chưa đủ căn cứ | C/TB | Tóm tắt AI mặc định chạy mô phỏng, chỉ gọi OpenAI khi đặt rõ; xóa tên, số điện thoại, BHYT, địa chỉ trước khi gửi; màn đồng ý báo trước | `CLINIC-API.md`, hồ sơ đánh giá tác động | Smart Scheduling chưa được đánh giá tác động dữ liệu |
| R06 | Người dùng tưởng prototype là dịch vụ thật | Tin là đã có lịch hoặc đã thanh toán | TB/TB | Dữ liệu, lịch và thanh toán đều giả lập; nhãn "Mô phỏng AI" khi không có key | Kiểm tra mọi màn kết quả có nhãn rõ | Thêm câu giới thiệu phạm vi trước mỗi buổi thử |
| R07 | Chuông thuốc không kêu | Lỡ liều | TB/TB | Xin quyền báo thức chính xác; từ chối thì vẫn có thông báo thường; nhắc lại sau 30 phút | `NHAC-THUOC.md` | Thử trên nhiều dòng máy Android có tiết kiệm pin mạnh |
| R08 | Liên kết nhầm máy người thân | Người khác xem lịch và thuốc | TB/T | QR dùng một lần, hết hạn sau 15 phút; máy nhận phải đồng ý; người được liên kết tắt được việc báo lỡ liều | `LIEN-KET-HAI-MAY.md` | — |
| R09 | Lưu ý trước khám sai với người bệnh cụ thể | Nhịn ăn hoặc ngừng thuốc không cần thiết | TB/TB | Ghi nguồn công khai trên từng lưu ý | `LUU-Y-TRUOC-KHAM.md` | Cần bác sĩ duyệt trước khi dùng thật |
| R10 | Người lớn tuổi khó dùng | Bỏ cuộc, phụ thuộc người khác | TB/C | Chữ lớn, vùng bấm rộng, giảm chuyển động, giọng nói, màn kiểm tra | Thử với 2–3 người 50–60+ | Chưa có log thử |
| R11 | Mẫu nghiên cứu lệch | Kết luận không đại diện | TB/C | Ghi rõ hạn chế trong insight | — | Chỉ 1 trong 4 người phỏng vấn trên 60 tuổi |
| R12 | Rút đồng ý nhưng dữ liệu còn trên máy chủ | Vi phạm quyền rút lại | TB/T | Web bác sĩ ẩn dữ liệu ngay lần tải sau | `CLINIC-API.md` | Xóa dữ liệu khi rút đồng ý chưa làm |
| R13 | AI tóm tắt trước khám viết sai nghĩa câu của người bệnh | Bác sĩ hiểu ngược diễn biến bệnh | TB/TB | Mỗi câu tóm tắt có "Xem câu gốc"; nhãn "AI tóm tắt"; số và tên thuốc được soát với câu gốc | [Kiểm thử AI thật](../05-prototype/docs/kiem-thu-ai-that.md): đã gặp một câu về huyết áp bị đọc ngược | Bộ kiểm tra chưa bắt được lỗi sai nghĩa; bác sĩ cần đối chiếu câu gốc với thông tin quan trọng |

## Đường chuyển tuyến khẩn cấp

- **Kích hoạt:** Khi dùng Smart Scheduling, mô tả của người bệnh có dấu hiệu nằm trong danh sách dấu hiệu cấp cứu, ví dụ khó thở, đau ngực dữ dội, ngất, yếu liệt. Danh sách chính thức sẽ do người có chuyên môn đề xuất và phân loại.
- **Cách phát hiện (đã duyệt, Nguyễn Mạnh Tú, 19/10/2026):** App luôn kiểm tra mô tả theo danh sách do chuyên môn duyệt; khi bật AI thật, model chỉ bổ sung thêm dấu hiệu, không thay thế danh sách. Hiện code chưa làm đúng như vậy: bản AI thật để model tự đánh giá, bản giả lập dùng danh sách tạm `URGENT_HINTS`. Phần sửa code sẽ làm ở một thread riêng.
- **Hệ thống làm gì:** Dừng luồng đặt lịch thường và gợi ý người dùng gọi 115 hoặc đến cơ sở y tế gần nhất ngay. Hệ thống chỉ gợi ý, không tự gọi; người dùng là người quyết định cuối cùng.
- **Kênh:** 115, số cấp cứu y tế toàn quốc.
- **Dự phòng:** Người dùng vẫn tự đặt lịch được theo luồng cơ bản; app không chặn họ.

| Hạng mục | Người duyệt | Ngày duyệt |
| --- | --- | --- |
| Danh sách và phân loại dấu hiệu | Người có chuyên môn, chưa chỉ định | — |
| Câu chữ thông báo | Người có chuyên môn, chưa chỉ định | — |
