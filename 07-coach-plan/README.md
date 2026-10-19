# 07 — Mình sẽ coach một nhóm làm bài này thế nào

**Trạng thái:** Bản nháp theo cách dự án MedicApp đã diễn ra, cho nhóm 5–10 người trong 4 tuần. Chờ chủ dự án duyệt.

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

## Nhịp 4 tuần

| Tuần | Việc chính | Đầu ra cần có | Bài học từ MedicApp |
| --- | --- | --- | --- |
| 1 | Chốt khoảnh khắc; mỗi người dùng thử app thật; phỏng vấn | Ghi chép dùng thử, ít nhất 6–8 log ẩn danh, phần lớn trong nhóm mục tiêu | MedicApp chỉ có 1/4 người trên 60 tuổi; nhóm đông nên chia nhau tìm đúng người |
| 2 | Tổng hợp insight cả nhóm, journey map, need statement, 3 best practice | Insight có mã bằng chứng, need statement chưa gắn giải pháp | Ghi log trước khi viết PRD để mọi quyết định truy được về trích dẫn |
| 3 | Prototype nhỏ nhất kiểm tra được nhu cầu; nhóm nghiên cứu chuẩn bị buổi thử song song | Prototype bấm được, kịch bản thử, danh sách người thử | Duyệt bố cục bằng prototype tương tác trước khi code giúp sửa rẻ hơn |
| 4 | Thử với 2–3 người, sửa, trình bày | Log thử, bảng thay đổi, deck tối đa 10 slide | Giữ thời gian cho vòng thử: nhiều tính năng mà chưa có log thử thì không chứng minh được nhu cầu |

## Nhịp gặp

- **Hằng ngày, 15 phút:** mỗi nhóm nhỏ báo việc đã xong, việc kế tiếp, chỗ bị chặn.
- **Cuối mỗi tuần, 60 phút:** cả nhóm xem đầu ra của tuần; coach hỏi bằng chứng, nhóm tự chọn việc tuần sau.
- **Giữa tuần 3:** duyệt prototype trước khi chốt kịch bản thử.

## Câu hỏi coach

- Bằng chứng nào dẫn đến nhận định này? Điều gì có thể bác bỏ nó?
- Đây là nhu cầu của người dùng hay giải pháp nhóm đã thích sẵn?
- Người thử đã làm gì, thay vì chỉ nói gì?
- Sau lần sửa, nhóm sẽ quan sát điều gì để biết có tiến bộ?
- Tính năng này giải quyết điểm đau nào trong journey map?

## Nguyên tắc phản hồi

Phản hồi vào hành vi và sản phẩm; để nhóm tự đề xuất bước tiếp theo. Với nhóm đông, đảm bảo mỗi nhóm nhỏ trình bày phần của mình trong buổi cuối tuần. Ghi rõ điều chưa biết, không dùng AI để tạo bằng chứng giả. Khi dùng AI để viết code hoặc tài liệu, ghi lại prompt và người kiểm tra như [prompt log](../05-prototype/prompts/README.md).
