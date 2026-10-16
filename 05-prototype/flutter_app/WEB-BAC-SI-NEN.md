# Bước 13: Nền cho web bác sĩ

Bước đầu của [plan triển khai web bác sĩ](https://claude.ai/code/artifact/354c51ed-e639-484b-95fd-b9f8207c036f). Người dùng app không thấy thay đổi.

## Thay đổi

- Tạo package [`packages/medic_core`](../packages/medic_core/README.md). `VisitResult`, `PrescriptionItem`, `MedicationCourse`, `DoseLogEntry` chuyển vào đó; app import `package:medic_core/medic_core.dart` thay cho hai file `domain` cũ. Hành vi không đổi.
- Thêm cách tính tuân thủ 30 ngày (`adherenceOf`) theo đúng bản bấm thử web bác sĩ, dùng cùng quy tắc liều quá giờ với màn Thuốc hôm nay.
- Backend thêm cơ sở dữ liệu phòng khám (`backend/src/db`), xem [backend README](../backend/README.md#cơ-sở-dữ-liệu-phòng-khám).

## Kiểm tra

- `dart test` trong `medic_core`: 7 test, gồm số liệu mẫu của bà Lan (Atorvastatin 18/30 liều = 60%, cụm 5 lần "Thấy khó chịu" từ 05/11).
- `npm test` trong `backend`: 33 test (thêm 5 test cơ sở dữ liệu).
- `flutter analyze` không có lỗi. `flutter test` (chạy trên Linux): 130 pass, 8 test ảnh chuẩn lệch như trên nhánh gốc (ảnh chuẩn tạo trên Windows, xem bước 5).
