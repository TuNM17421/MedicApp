# Bước 11: Kết quả khám và đơn thuốc

## Người dùng thấy gì

- Ở **Chi tiết lịch hẹn** (lịch đã xác nhận) có mục **Kết quả khám**. Trước khi có kết quả, nút **Mô phỏng: bác sĩ gửi kết quả** thay cho web bác sĩ thật.
- Khi có kết quả, mục này thành thẻ **Kết quả khám và đơn thuốc** (số loại thuốc, ngày tái khám).
- Màn hình **Kết quả khám** có hai cách xem:
  - **Dễ đọc**: chẩn đoán, mỗi thuốc một thẻ chữ to ("Sáng 1 viên, sau ăn", "30 viên · dùng 30 ngày"), lời dặn, ngày tái khám.
  - **Bản đơn thuốc**: bố cục giống mẫu đơn của Thông tư 18/2018/TT-BYT (tên đơn vị, điện thoại, họ tên, tuổi, cân nặng, nam/nữ, mã thẻ BHYT, địa chỉ, chẩn đoán, thuốc điều trị, lời dặn, ngày kê, bác sĩ, "Khám lại xin mang theo đơn này").

## Dữ liệu

- `lib/features/records/domain/visit_result.dart`: `VisitResult` gồm các trường của mẫu đơn cộng với mã lượt khám. Mỗi dòng thuốc (`PrescriptionItem`) tách sẵn tên, hàm lượng, dạng, số lượng, các liều theo buổi (sáng/trưa/chiều/tối), trước/sau ăn, số ngày và ghi chú, để bước 12 dùng làm lịch nhắc. `usageLine` ghi lại thành câu như bác sĩ viết trên đơn giấy.
- Kết quả gắn với **mã lượt khám**, nên luôn vào đúng hồ sơ, không phải dò theo họ tên và tuổi.
- `lib/features/records/data/doctor_portal.dart`: `DoctorPortal` là giao diện cho web bác sĩ. `MockDoctorPortal` kê đơn mẫu theo các bệnh đang theo dõi của người khám (tăng huyết áp, đái tháo đường, rối loạn lipid máu, gút, viêm dạ dày). Đây là dữ liệu mẫu cho bản thử, không phải lời khuyên dùng thuốc. Ngày tái khám bằng ngày khám cộng số ngày dùng thuốc dài nhất.
- Lịch hẹn và kết quả giờ thuộc về từng tài khoản (trước đây lịch hẹn dùng chung khi đổi tài khoản), và được lưu vào kho mã hóa của bước 10 khi chủ tài khoản đã đồng ý.

## Giới hạn

- Chưa có web bác sĩ thật; khi có, chỉ cần thay `MockDoctorPortal`.
- Mẫu đơn dùng theo file người dùng gửi (Thông tư 18/2018). Thông tư 26/2025/TT-BYT là quy định mới hơn về kê đơn ngoại trú; chưa đối chiếu mẫu của thông tư này.
