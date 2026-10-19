# Phân tích và tổng hợp insight

**Trạng thái:** Đang chờ duyệt.

| Mã | Chủ đề | Bằng chứng | Diễn giải | Bằng chứng trái chiều | Hạn chế |
| --- | --- | --- | --- | --- | --- |
| INS-01 | Quá nhiều lựa chọn phải tự quyết | [P3-Q02](logs/P3.md), OBS-02, [DT-O02, DT-O03](ghi-chep-dung-thu.md) | Chuỗi chọn nơi khám → chuyên khoa → bác sĩ → giờ là điểm làm người lớn tuổi phải nhờ người khác | [P1-Q03](logs/P1.md), [P2-Q02](logs/P2.md): người trẻ quen công nghệ không thấy khó | Chỉ 1 người trên 60 tuổi (P3) |
| INS-02 | Không biết bệnh thuộc chuyên khoa nào | [P4-Q02](logs/P4.md), [P3-Q03](logs/P3.md), [DT-O13](ghi-chep-dung-thu.md) | Người bệnh mô tả được triệu chứng nhưng không ánh xạ được sang chuyên khoa; "Đặt lịch theo triệu chứng" của MyVinmec dùng danh sách cố định và khớp từ khóa nên không nhận cách diễn đạt riêng hay lỗi chính tả | — | Gợi ý chuyên khoa từ triệu chứng cần chuyên môn duyệt |
| INS-03 | Tìm lịch trống bằng cách thử từng bác sĩ | [DT-O03, DT-O04](ghi-chep-dung-thu.md), OBS-03 | Hết lịch hoặc lỗi khiến người dùng bỏ cuộc; hệ thống nên tìm bác sĩ còn lịch gần ngày mong muốn | — | Một phiên dùng thử của chủ dự án |
| INS-04 | Muốn ưu tiên nơi khám gần | [P1-Q02](logs/P1.md) | Vị trí hiện tại là gợi ý hợp lý cho bước chọn nơi khám | Chỉ một người nêu | — |
| INS-05 | Muốn nói thay vì bấm | [P3-Q03](logs/P3.md) | Giọng nói có thể thay chuỗi thao tác cho người không quen bấm chọn | — | Mong muốn tự nêu, chưa kiểm chứng hành vi |
| INS-06 | Đặt hộ và theo dõi thuốc cho người thân | [P4-Q01, P4-Q03](logs/P4.md), [P3-Q01](logs/P3.md), OBS-01 | Người chăm sóc là người dùng thật của app, cần hồ sơ người thân và theo dõi việc uống thuốc | — | — |
| INS-07 | Không gửi được thông tin cho bác sĩ trước khám | [DT-O05](ghi-chep-dung-thu.md) | Lịch hẹn chỉ có giờ bắt đầu và lý do khám ngắn | — | Suy luận từ dùng thử, chưa có người tham gia nêu |

## Hướng giải pháp

Hệ thống tự điền gợi ý phù hợp bối cảnh để người dùng ít phải chọn:

- Đề xuất nơi khám gần nhất so với vị trí hiện tại (INS-04).
- Nhận mô tả triệu chứng bằng lời tự nhiên (nói hoặc gõ), AI đề xuất chuyên khoa phù hợp nhất (INS-02, INS-05).
- Người dùng nói hoặc điền thời gian muốn khám, hệ thống tìm bác sĩ có lịch khớp hoặc gần nhất (INS-03).
- Theo dõi lịch uống thuốc và tái khám, kể cả cho người thân (INS-06).

## Khoảnh khắc ưu tiên

**Người lớn tuổi tự đặt một lượt khám ngoại trú và biết rõ mình đã có lịch nào.** Chọn vì INS-01 và INS-03 làm người dùng bỏ cuộc hoặc phải nhờ người khác, có bằng chứng từ cả phỏng vấn (P3, P4) và dùng thử. Hạn chế: mẫu 4 người, chỉ P3 trên 60 tuổi, P4 49 tuổi; cần thêm người 50–60+ trước khi suy rộng.
