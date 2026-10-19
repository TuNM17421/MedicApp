# Kiểm thử AI với API thật

**Ngày:** 19/10/2026. **Người thực hiện:** Nguyễn Mạnh Tú. **Model:** `gpt-6-luna`.

Cả Đặt lịch thông minh và Tóm tắt trước khám đều chạy được với AI thật. Dữ liệu người bệnh là tài khoản mẫu Phạm Thị Lan, không phải người thật.

- Video 1 phút 30 giây: [test-ai-that.mp4](anh-ai-that/test-ai-that.mp4).
- Ảnh chụp: [anh-ai-that/](anh-ai-that/).

## Đặt lịch thông minh

Đăng nhập app bằng Phạm Thị Lan và nhập một câu: "Mấy hôm nay tôi hay chóng mặt, đau đầu, đo huyết áp được 160. Tôi muốn khám sáng thứ Hai tuần sau ở An Bình, có bảo hiểm y tế."

| Kết quả | Ảnh |
| --- | --- |
| Khoảng 4 giây sau, AI điền đủ đề xuất mà không cần hỏi thêm: khám BHYT, Phòng khám Đa khoa An Bình, khoa Nội tổng quát kèm lý do "khám chóng mặt và đau đầu", BS. Nguyễn Thu Hà, 07:30 thứ Hai 19/10 | [01](anh-ai-that/01-dat-lich-nhap-yeu-cau.png), [02](anh-ai-that/02-dat-lich-de-xuat-1.png), [03](anh-ai-that/03-dat-lich-de-xuat-2.png) |
| Bấm xác nhận thì sang đúng bước thanh toán. Màn hình không còn nhãn "Mô phỏng AI" | [04](anh-ai-that/04-dat-lich-thanh-toan.png) |

## Tóm tắt trước khám

Trả lời 4 câu hỏi trước khám trong app, có nhắc "tức ngực khi leo cầu thang".

| Kết quả | Ảnh |
| --- | --- |
| Khoảng 4 giây sau, web bác sĩ hiện tóm tắt nhãn "AI tóm tắt" gồm 3 mục và cờ đỏ "Người bệnh có nhắc tới: tức ngực" | [05](anh-ai-that/05-cau-hoi-truoc-kham.png), [06](anh-ai-that/06-bac-si-tom-tat-ai.png) |
| Mỗi câu tóm tắt đều mở được câu gốc của người bệnh | [07](anh-ai-that/07-bac-si-xem-cau-goc.png) |

## Vấn đề phát hiện

1. **Một câu tóm tắt sai nghĩa:** "huyết áp tuần trước chỉ khoảng 140, nặng hơn hiện tại". Người bệnh muốn nói hiện tại nặng hơn tuần trước, nên câu này dễ đọc ngược. Bộ kiểm tra hiện chỉ soát số và tên thuốc có trong câu gốc, nên không bắt được lỗi sai nghĩa. Ghi vào [sổ rủi ro R13](../../06-rui-ro-dao-duc/README.md).
2. **Tóm tắt có chuyện đau gối:** lấy từ dữ liệu mẫu có sẵn của Phạm Thị Lan, không phải AI tự thêm.
