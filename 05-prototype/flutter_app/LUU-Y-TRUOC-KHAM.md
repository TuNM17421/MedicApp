# Lưu ý cá nhân hóa trước khi khám — bước 7

Ngày 2026-10-15. App đọc hồ sơ người khám (bệnh đang theo dõi, tuổi, quan hệ) và lịch hẹn (chuyên khoa, ngày giờ) để đưa ra lưu ý riêng, ví dụ: “Bạn có lịch khám Nội tiết lúc 08:00 sáng mai. Vì đang theo dõi đái tháo đường, bác sĩ có thể cho xét nghiệm đường huyết lúc đói: vui lòng nhịn ăn từ nửa đêm nay (8 tiếng trước).”

Đây là **quy tắc chạy trong app** (mô phỏng AI), không gọi dịch vụ AI hay gửi hồ sơ đi đâu, giữ quy tắc không kết nối dịch vụ thật.

## Dữ liệu trước bước này

Dữ liệu mock trước đây **không có danh mục bệnh**: chỉ có 7 chuyên khoa (Nội tổng quát, Tim mạch, Cơ Xương Khớp, Tai Mũi Họng, Mắt, Nội tiết, Nhi khoa) và một bộ từ khóa triệu chứng trong backend mô phỏng để gợi ý khoa (đau ngực, huyết áp → Tim mạch; tiểu đường, tuyến giáp → Nội tiết…).

## 5 bệnh và cách chuẩn bị

| Bệnh | Khoa | Thường làm | Chuẩn bị chính | Nguồn |
| --- | --- | --- | --- | --- |
| Đái tháo đường | Nội tiết | Xét nghiệm đường huyết lúc đói | Nhịn ăn ít nhất 8 tiếng, chỉ uống nước lọc; không cà phê, kẹo cao su, thuốc lá khi nhịn | [MedlinePlus](https://medlineplus.gov/lab-tests/blood-glucose-test/), [MedlinePlus fasting](https://medlineplus.gov/lab-tests/fasting-for-a-blood-test/) |
| Rối loạn mỡ máu | Tim mạch, Nội tiết | Xét nghiệm mỡ máu | Nhịn ăn 9–12 tiếng (app nhắc mốc 9), uống nước lọc được; ngừng rượu bia, đồ có gas ít nhất 24 tiếng | [MedlinePlus](https://medlineplus.gov/lab-tests/cholesterol-levels/), [MEDLATEC](https://medlatec.vn/tin-tuc/xet-nghiem-mo-mau-co-can-nhin-an-khong-giai-dap-chi-tiet) |
| Tăng huyết áp | Tim mạch | Đo huyết áp | Không hút thuốc, cà phê/trà, tập thể dục trong 30 phút trước; đi vệ sinh; nghỉ yên 5 phút | [AHA](https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/monitoring-your-blood-pressure-at-home) |
| Gút | Cơ Xương Khớp | Xét nghiệm acid uric máu | Nhịn ăn ít nhất 4 tiếng, uống nước lọc được; tránh rượu bia (app nhắc 24 tiếng); báo bác sĩ nếu dùng aspirin, ibuprofen, vitamin C | [Tâm Anh](https://tamanhhospital.vn/xet-nghiem-acid-uric-mau/), [UCSF Health](https://www.ucsfhealth.org/medical-tests/003476) |
| Viêm dạ dày | Nội tổng quát | Nội soi dạ dày | Nhịn ăn 6–8 tiếng, ngừng nước lọc 2 tiếng, sữa/đồ uống có màu 4 tiếng; thuốc hằng ngày uống trước 3 tiếng; có người nhà đưa về nếu gây mê | [Tâm Anh](https://tamanhhospital.vn/huong-dan-nguoi-benh-truoc-khi-noi-soi/), [HealthPartners](https://www.healthpartners.com/content/dam/brand-identity/pdfs/care/Esophagogastroduodenoscopy-EGD-preparing-for-your-procedure.pdf) |

Mốc 24 tiếng kiêng rượu bia cho gút là lựa chọn thận trọng của app: nguồn chỉ nói rượu làm sai lệch kết quả, không nêu số giờ.

## Cá nhân hóa

- **Khớp hồ sơ với lịch:** chỉ nhắc khi người khám có bệnh đó **và** lịch thuộc khoa liên quan. Lịch đã qua, lịch thanh toán lỗi hoặc khoa không liên quan thì không nhắc.
- **Giờ cụ thể:** tính ngược từ giờ hẹn và nói theo cách thường ngày: “nửa đêm nay”, “14:30 chiều mai”, “Thứ Bảy 17/10”. Nếu mốc đã qua (đặt lịch sát giờ), app nói phải làm gì bây giờ và nhắc báo nhân viên nếu đã ăn hoặc đã uống rượu.
- **Gọi đúng người:** “Bạn…” cho hồ sơ bản thân, “Mẹ Phạm Thị Lan…” cho người thân.
- **Kết hợp bệnh:** người đang theo dõi đái tháo đường mà phải nhịn ăn được nhắc hỏi bác sĩ về thuốc tiểu đường/insulin, không tự ý bỏ thuốc. Người từ 60 tuổi đi nội soi được nhắc cần người nhà đưa về, không tự lái xe.
- **Nơi hiển thị:** thẻ “Lưu ý trước khi khám” ở Trang chủ (lịch gần nhất), mục “Chuẩn bị trước khi khám” trong Chi tiết lịch hẹn và màn kết quả đặt lịch, kèm nguồn và câu “chỉ để tham khảo, cơ sở khám dặn khác thì làm theo cơ sở”.
- **Khai báo bệnh:** Chi tiết hồ sơ có mục “Bệnh đang theo dõi” để bật/tắt 5 bệnh. Gia đình mẫu: Phạm Văn Hòa có đái tháo đường và tăng huyết áp; Phạm Thị Lan có gút và rối loạn mỡ máu.

## Mã nguồn

| Tệp | Nội dung |
| --- | --- |
| `lib/features/visit_prep/visit_prep_catalog.dart` | 5 bệnh, mốc giờ, các bước và nguồn |
| `lib/features/visit_prep/visit_prep.dart` | `adviseVisit` (quy tắc cá nhân hóa), `visitPrepNotesProvider`, `prepClockProvider` |
| `lib/features/visit_prep/visit_prep_widgets.dart` | Thẻ Trang chủ, mục trong chi tiết lịch hẹn, chọn bệnh trong hồ sơ |

`PreviewProfile` có thêm `conditions`; `VisitSummary` có thêm `patientId`, `departmentId`.

## Kiểm tra

`test/visit_prep/visit_prep_test.dart` (8 test): câu nhắc đúng như ví dụ, khoa Tim mạch chỉ nhắc bệnh người đó có, gọi tên người thân và tính 24 tiếng, mốc đã qua, nội soi với người lớn tuổi, các trường hợp không nhắc, mỗi bệnh có nguồn, và luồng Trang chủ → chi tiết → bỏ chọn bệnh thì hết nhắc. Toàn bộ: 93 test pass, 8 test ảnh chuẩn vẫn lệch font như trước.

**Cần chuyên môn duyệt trước khi dùng thật:** nội dung y khoa lấy từ hướng dẫn công khai cho người bệnh, chưa được bác sĩ duyệt; mỗi cơ sở có thể dặn khác.
