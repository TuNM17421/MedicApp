# 03 — Need statement

**Trạng thái:** Bản nháp do AI soạn từ insight đã có bằng chứng, chờ chủ dự án duyệt.

## Phát biểu nhu cầu

**Người lớn tuổi muốn tự đi khám** cần **mô tả vấn đề sức khỏe theo cách của mình và nhận được một lịch khám phù hợp mà không phải tự chọn qua nhiều lớp lựa chọn** khi **đặt một lượt khám ngoại trú** vì **họ không biết bệnh thuộc chuyên khoa nào, bỏ cuộc khi phải thử từng bác sĩ để tìm lịch trống, và hiện phải nhờ con cái đặt hộ**.

## Chuỗi bằng chứng

| Log/trích dẫn/quan sát | Insight | Điểm đau trong journey | Nhu cầu rút ra |
| --- | --- | --- | --- |
| P3-Q01, P3-Q02, OBS-02 | INS-01 | PAIN-01 | Tự hoàn thành mà không cần người khác |
| P4-Q02, P3-Q03 | INS-02, INS-05 | PAIN-02 | Mô tả triệu chứng thay vì chọn chuyên khoa |
| DT-O03, DT-O04, OBS-03 | INS-03 | PAIN-04 | Được tìm sẵn lịch còn trống gần ngày mong muốn |
| P4-Q01, P4-Q03 | INS-06 | PAIN-06 | Người chăm sóc theo dõi được lịch và thuốc của người thân |

## Phạm vi và tiêu chí thành công

**Prototype hỗ trợ:** Đặt lịch cơ bản có màn kiểm tra; Smart Scheduling (nói/gõ triệu chứng, gợi ý chuyên khoa, gợi ý giờ còn chỗ sớm nhất, gợi ý cơ sở gần); hồ sơ người thân; nhắc khám, nhắc thuốc.

**Ngoài phạm vi:** Chẩn đoán, phân luồng cấp cứu tự động, dự đoán thời gian chờ khi chưa có dữ liệu vận hành, kết nối hệ thống bệnh viện thật.

**Tiêu chí quan sát được khi thử với 2–3 người 50–60+ (đề xuất, chờ duyệt):**

1. Tự đặt xong một lượt khám mà không cần người hỗ trợ can thiệp.
2. Sau khi đặt, nói lại đúng lịch của ai, khoa nào, ở đâu, lúc nào.
3. Khi gợi ý sai hoặc hết chỗ, tự sửa được hoặc chuyển sang tự chọn mà không bỏ cuộc.
4. Ghi số lần cần trợ giúp và bước bị kẹt để so sánh sau mỗi lần sửa.
