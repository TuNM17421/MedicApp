# medic_core

Phần dùng chung giữa app người bệnh (`flutter_app`) và web bác sĩ (`doctor_web`, bước 14). Thuần Dart, không phụ thuộc Flutter, nên hai bên và test tính ra cùng một con số.

| File | Nội dung |
| --- | --- |
| `lib/src/visit_result.dart` | `VisitResult`, `PrescriptionItem`, `Dose`: đơn thuốc theo mẫu Thông tư 18/2018/TT-BYT, câu ghi trên đơn (`usageLine`). Chuyển từ `flutter_app/lib/features/records/domain/`. |
| `lib/src/medication.dart` | `MedicationCourse`, `DoseLogEntry`, `SkipReason`, trạng thái liều trên màn Thuốc hôm nay. Chuyển từ `flutter_app/lib/features/meds/domain/`. |
| `lib/src/adherence.dart` | Tỷ lệ tuân thủ cho web bác sĩ: số liều đã uống trên số liều đã đến giờ, ngưỡng 80%, từng ngày (đủ, thiếu, bỏ), lý do bỏ liều và nhận xét dạng sự kiện. |

## Quy tắc tính tuân thủ

- Một liều được tính khi đã ghi (uống hoặc bỏ) hoặc đã quá giờ 60 phút, giống quy tắc màn Thuốc hôm nay. Liều chưa đến giờ không tính.
- Liều quá giờ mà không ghi gì được tính là không uống, lý do "Không ghi nhận".
- Tỷ lệ = liều đã uống / liều đã đến giờ, làm tròn. Từ 80% là **Đạt**, 60–79% là **Dưới 80%**, dưới 60% là **Thấp**.
- Nhận xét chỉ nêu sự kiện từ nhật ký (số liều bỏ, lý do nhiều nhất, một lý do ngoài "Quên uống" lặp từ 3 lần trở lên và đều nằm trong 14 ngày gần nhất). Không suy luận về bệnh, không qua AI.

## Kiểm tra

```powershell
Set-Location .\05-prototype\packages\medic_core
dart pub get
dart analyze
dart test
```
