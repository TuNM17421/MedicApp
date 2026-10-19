# 07 — Mình sẽ coach một nhóm làm bài này thế nào

**Trạng thái:** Đã duyệt (Nguyễn Mạnh Tú, 19/10/2026). Áp dụng cho nhóm 5–10 người, một nhịp 6 tuần.

## Mục tiêu

Giúp nhóm đi từ quan sát có bằng chứng đến một nhu cầu rõ ràng, prototype có thể thử và bài trình bày trung thực về kết quả.

## Cách chia nhóm

Với 5–10 người, chia thành 3 nhóm nhỏ có trưởng nhóm, và một người điều phối chung (có thể kiêm trưởng nhóm):

| Nhóm nhỏ | Số người | Việc chính |
| --- | --- | --- |
| Nghiên cứu | 2–3 | Dùng thử app, phỏng vấn, ẩn danh log, giữ chuỗi bằng chứng, chạy buổi thử |
| Thiết kế | 2–3 | Journey map, need statement, best practice, prototype tương tác, kịch bản thử |
| Kỹ thuật | 1–3 | Dựng prototype, dữ liệu giả lập, quyền riêng tư, ghi prompt AI |
| Điều phối | 1 | Lịch, sổ rủi ro, deck, AI disclosure, kiểm tra repo |

Nhóm 5 người: mỗi nhóm nhỏ 1–2 người, điều phối kiêm nghiên cứu. Nhóm 10 người: thêm người cho nghiên cứu để phỏng vấn được nhiều người 50–60+ hơn.

## Nhịp 6 tuần

| Tuần | Việc chính | Đầu ra cần có | Bài học từ MedicApp |
| --- | --- | --- | --- |
| 1 | Chốt khoảnh khắc, phân vai; mỗi người dùng thử app thật; viết interview guide | Ghi chép dùng thử, interview guide đã duyệt, danh sách người cần phỏng vấn | Dùng thử cả app lẫn website, thử mọi cách đặt (theo bác sĩ, chuyên khoa, triệu chứng) để thấy giới hạn thật |
| 2 | Phỏng vấn và ẩn danh log | Ít nhất 6–8 log, phần lớn trong nhóm mục tiêu | MedicApp chỉ có 1/4 người trên 60 tuổi; nhóm đông nên chia nhau tìm đúng người |
| 3 | Tổng hợp insight cả nhóm, journey map, need statement, 3 best practice | Insight có mã bằng chứng, need statement đã duyệt | Ghi log trước khi viết PRD để mọi quyết định truy được về trích dẫn |
| 4 | PRD và prototype tương tác; duyệt bố cục | Prototype bấm được, dữ liệu giả lập rõ ràng | Duyệt bố cục bằng prototype tương tác trước khi code giúp sửa rẻ hơn |
| 5 | Dựng bản chạy được; kiểm thử với AI thật nếu có; nhóm nghiên cứu chuẩn bị buổi thử | Bản chạy trên điện thoại, kịch bản thử, sổ rủi ro | Test với API thật sớm: MedicApp phát hiện AI tóm tắt sai nghĩa chỉ khi chạy thật |
| 6 | Thử với 2–3 người, sửa, trình bày | Log thử, bảng thay đổi, deck tối đa 10 slide | Giữ đủ thời gian cho vòng thử: nhiều tính năng mà chưa có log thử thì không chứng minh được nhu cầu |

## Nhịp gặp

- **Hằng ngày, 15 phút:** mỗi nhóm nhỏ báo việc đã xong, việc kế tiếp, chỗ bị chặn.
- **Cuối mỗi tuần, 60 phút:** cả nhóm xem đầu ra của tuần; coach hỏi bằng chứng, nhóm tự chọn việc tuần sau.
- **Cuối tuần 3 và tuần 4:** hai mốc duyệt chính, need statement rồi đến prototype.

## Câu hỏi coach

- Bằng chứng nào dẫn đến nhận định này? Điều gì có thể bác bỏ nó?
- Đây là nhu cầu của người dùng hay giải pháp nhóm đã thích sẵn?
- Người thử đã làm gì, thay vì chỉ nói gì?
- Sau lần sửa, nhóm sẽ quan sát điều gì để biết có tiến bộ?
- Tính năng này giải quyết điểm đau nào trong journey map?

## Nguyên tắc phản hồi

Phản hồi vào hành vi và sản phẩm; để nhóm tự đề xuất bước tiếp theo. Với nhóm đông, đảm bảo mỗi nhóm nhỏ trình bày phần của mình trong buổi cuối tuần. Ghi rõ điều chưa biết, không dùng AI để tạo bằng chứng giả. Khi dùng AI để viết code hoặc tài liệu, ghi lại prompt và người kiểm tra như [prompt log](../05-prototype/prompts/README.md).
