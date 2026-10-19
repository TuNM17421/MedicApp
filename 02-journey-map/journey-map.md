# Journey map — Người lớn tuổi tự đặt một lượt khám ngoại trú

**Trạng thái:** Bản nháp do AI dựng từ log P1–P4 và ghi chép dùng thử MyVinmec; chờ chủ dự án duyệt. Cảm xúc chỉ ghi khi có trích dẫn hoặc quan sát.

- **Người dùng:** Người 50–60+ tự đặt khám, đại diện bởi P3 (71 tuổi); người chăm sóc đặt hộ, đại diện bởi P4.
- **Mục tiêu:** Đặt được một lượt khám đúng chuyên khoa và biết rõ lịch của mình.
- **Bắt đầu:** Có vấn đề sức khỏe cần đi khám. **Kết thúc:** Có lịch xác nhận, biết cần làm gì tiếp.

| Giai đoạn | Hành động | Điểm chạm | Suy nghĩ/cảm xúc có bằng chứng | Điểm đau | Bằng chứng | Cơ hội |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Quyết định đặt | Tự mở app hoặc nhờ con | Con cái, app | "Tôi chưa bao giờ tự đặt lịch cả, vì không biết dùng" | PAIN-01 Phụ thuộc người khác | P3-Q01, P3-Q02 | Lối vào một nút, cho đặt hộ có kiểm soát |
| 2. Chọn cách đặt và chuyên khoa | Chọn theo bác sĩ, chuyên khoa hay triệu chứng | App, website | "Không chắc là bệnh của tôi thuộc chuyên khoa nào" | PAIN-02 Không biết chọn chuyên khoa | P4-Q02, DT-O02 | Nói/gõ triệu chứng, gợi ý chuyên khoa có giới hạn |
| 3. Chọn nơi khám | Chọn cơ sở | App, website | — | PAIN-03 Không có gợi ý theo vị trí | P1-Q02, DT-O06 | Gợi ý cơ sở gần nhất |
| 4. Tìm bác sĩ và giờ | Thử từng bác sĩ, từng ngày | App | Bỏ cuộc khi không có lịch hoặc gặp lỗi | PAIN-04 Thử lần lượt, chờ hơn 4 giây mỗi lần | DT-O03, DT-O04, OBS-03 | Hệ thống tìm bác sĩ còn lịch gần ngày mong muốn |
| 5. Kiểm tra và xác nhận | Đọc thông tin đặt hẹn | App | — | PAIN-05 Không có giờ kết thúc, không gửi được tình trạng cho bác sĩ | DT-O05 | Màn kiểm tra rõ ràng, câu hỏi trước khám |
| 6. Sau khi đặt | Chờ ngày khám, khám, uống thuốc | App, tin nhắn | "Tôi hay quên uống" | PAIN-06 Quên thuốc, người thân không theo dõi được | P4-Q01, P4-Q03 | Nhắc khám, nhắc thuốc, liên kết người thân |

## Điểm đau ưu tiên

PAIN-02 và PAIN-04 là hai điểm prototype xử lý trước (Smart Scheduling và gợi ý giờ còn chỗ), vì cả phỏng vấn và dùng thử đều cho thấy chúng làm người dùng bỏ cuộc hoặc phải nhờ người khác.

## Giả thuyết chưa xác nhận

- Giọng nói giúp người lớn tuổi tự đặt được (P3-Q03 là mong muốn, chưa quan sát hành vi).
- PAIN-03 chỉ có một người nêu.

## Đối chiếu với prototype hiện tại (19/10/2026)

"Đã giải quyết" nghĩa là prototype đã có tính năng cho điểm đau này với dữ liệu giả lập. Chưa điểm nào được kiểm chứng với người dùng 50–60+.

| Điểm đau | Trạng thái | Prototype đã có | Còn thiếu |
| --- | --- | --- | --- |
| PAIN-01 Phụ thuộc người khác | Một phần | Trang chủ chỉ ưu tiên Đặt lịch và Xem lịch hẹn; Smart Scheduling hỏi từng câu; hồ sơ người thân từ QR CCCD; con đặt hộ được ([BOOKING](../05-prototype/flutter_app/BOOKING.md), [AUTH-CCCD](../05-prototype/flutter_app/AUTH-CCCD.md)) | Chưa có log thử chứng minh người 50–60+ tự đặt được |
| PAIN-02 Không biết chọn chuyên khoa | Một phần | Nói hoặc gõ triệu chứng, đề xuất chuyên khoa kèm lý do, sửa và hoàn tác được ([SMART-SCHEDULING](../05-prototype/flutter_app/SMART-SCHEDULING.md)) | Chưa gọi AI bằng key thật, chưa đo chất lượng nhận giọng tiếng Việt; gợi ý khoa chưa có chuyên môn duyệt |
| PAIN-03 Không gợi ý theo vị trí | Đã giải quyết | Bản đồ cơ sở, gợi ý cơ sở gần nhất phù hợp BHYT, từ chối quyền vị trí vẫn đặt được (PR #16) | Tọa độ cơ sở là dữ liệu minh họa |
| PAIN-04 Thử từng bác sĩ để tìm lịch | Một phần | Smart Scheduling chọn giờ còn chỗ sớm nhất theo ngày/buổi mong muốn; luồng cơ bản có lựa chọn "bác sĩ còn lịch"; skeleton khi tải giờ; xử lý giờ vừa hết chỗ | Lịch là giả lập nên chưa giải quyết được độ trễ hơn 4 giây của hệ thống thật (DT-O04) |
| PAIN-05 Không có giờ kết thúc, không gửi được tình trạng | Một phần | Câu hỏi trước khám gửi tới bác sĩ sau khi đồng ý chia sẻ; web bác sĩ có tóm tắt dẫn về câu gốc (bước 16–17) | Lịch hẹn vẫn chỉ có giờ bắt đầu, chưa có giờ kết thúc dự kiến |
| PAIN-06 Quên thuốc, người thân không theo dõi được | Đã giải quyết | Nhắc thuốc theo đơn, chuông báo như báo thức, liên kết máy người thân và báo lỡ liều sau 60 phút ([NHAC-THUOC](../05-prototype/flutter_app/NHAC-THUOC.md), [LIEN-KET-HAI-MAY](../05-prototype/flutter_app/LIEN-KET-HAI-MAY.md)) | Chưa có thông báo đẩy: máy người thân chỉ biết lỡ liều khi app đang mở |

**Ngoài journey map:** Lỗi kỹ thuật hiện ra cho người dùng (DT-O08) và chatbot trình bày khó nhìn (DT-O12) là vấn đề của MyVinmec, prototype không xử lý. Sàng lọc đột quỵ kết luận nguy cơ chỉ từ một câu Có (DT-O10); prototype chỉ có hướng dẫn gọi 115 khi phát hiện dấu hiệu cấp cứu trong Smart Scheduling.
