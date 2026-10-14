> **Thư mục tạm.** Chứa prototype đã duyệt để agent khác đọc khi triển khai Flutter. Xóa thư mục này sau khi triển khai xong.

# Prototype đặt lịch khám — vòng 1 (bàn giao để duyệt)

Ngày 2026-10-14. Dựng theo `05-prototype/prompts/prototype-agent-brief.md`, nguồn chính `05-prototype/prd-smart-scheduling.md`. Chưa áp dụng vào Flutter, chưa commit/push, không sửa `05-prototype/flutter_app/`.

## 1. Cách mở

- **Bấm thử online:** mở link Artifact trong thread (riêng tư, chỉ bạn xem được trừ khi bạn chia sẻ).
- **Mở cục bộ:** mở `index.html` bằng Chrome/Edge/Safari. Một file duy nhất, không cần backend hay cài đặt. Cần mạng chỉ để tải font Be Vietnam Pro; không có mạng thì dùng font hệ thống.
- Nếu muốn đưa vào repo theo brief: đặt file tại `05-prototype/interactive-prototype/index.html` (tôi chưa đưa vào repo vì bạn yêu cầu không commit).
- **Xem dạng điện thoại:** trên máy tính, app hiển thị trong khung 412 × 915; bảng người duyệt ở bên phải. Trên điện thoại, bấm nút “Kịch bản demo” ở dải tối phía trên.

**Reset dữ liệu:** mọi dữ liệu chỉ nằm trong bộ nhớ trang. Tải lại trang, chọn một kịch bản, hoặc bấm “Đặt lại toàn bộ dữ liệu” đều đưa về trạng thái ban đầu. Không lưu gì vào trình duyệt.

## 2. Bảng người duyệt (tách khỏi giao diện app)

- Nút T01–T06: đặt lại dữ liệu, cài sẵn kết quả cố định và hiện các bước cần bấm.
- Kết quả thanh toán trả trước tiếp theo: Thành công / Lỗi / Mất kết nối / Trả rồi, lịch chờ.
- Lỗi mạng khi tải giờ (xảy ra 1 lần, bấm “Thử lại” sẽ tải được).
- Cơ sở đã xác nhận lịch đang chờ (dùng cho T06).
- Khung 360 × 800 / 412 × 915 và “Chữ 200%”.

## 3. Mapping kịch bản

| Kịch bản | Cách mở | Cần quan sát |
| --- | --- | --- |
| T01 Tự đặt khám dịch vụ | Bấm T01, đi từ trang bắt đầu | S00 → 6 bước → kết quả có mã lịch mẫu; mở lại ở “Xem lịch hẹn” |
| T02 BHYT cho người thân | Bấm T01 hoặc T02 → Khám BHYT → Phạm Thị Lan (mẹ) | Tên người khám ở đầu bước 3–6; Bệnh viện Sông Xanh không nhận BHYT, có giải thích và nút “Đổi hình thức khám”, không tự đổi; thanh toán chỉ có “trả tại viện”, quyền lợi chưa xác nhận |
| T03 Sửa từ trang Kiểm tra | Bấm T03 (mở sẵn trang Kiểm tra) | Sửa nơi khám → Sông Xanh: giữ khoa Tim mạch, chọn lại giờ. Sửa → Hòa Lạc: chọn lại khoa. Nút “Lưu và về trang Kiểm tra”. Sửa người khám: ghi chú lý do khám bị xóa; cháu An mới chọn được Nhi khoa |
| T04 Giờ vừa hết chỗ | Bấm T04 → “Tiếp tục: Thanh toán” | Báo giờ vừa có người đặt trước khi trả tiền; về bước 4 giữ mọi lựa chọn khác; giờ cũ hiện “Hết chỗ”; không tự chọn giờ thay |
| T05a Thanh toán lỗi | Bấm T05a → Thanh toán → Ví điện tử | Màn hình lỗi: chưa trừ tiền, chưa tạo lịch; “Thử thanh toán lại” (lần sau thành công) hoặc “Đổi cách thanh toán” |
| T05b Đang xử lý / mất kết nối | Bấm T05b → Thanh toán → Thẻ | “Đang kiểm tra thanh toán”, dặn không trả lại; kiểm tra lần 1 chưa có kết quả, lần 2 xác nhận. Về trang chính: lịch nằm ở mục “Đang xử lý” |
| T06 Đã trả tiền, lịch chưa xác nhận | Bấm T06 → Thanh toán → Ví | “Đã nhận thanh toán, lịch chưa được xác nhận”, có mã giao dịch, không có mã lịch; bật “Cơ sở đã xác nhận…” rồi kiểm tra lại mới có mã lịch |

Nút thanh toán bị khóa trong lúc xử lý; lịch được gắn với bản đặt nên bấm lặp không tạo lịch trùng.

**Hoãn ở vòng này (chưa làm):** T07 gợi ý khoa bằng AI, T08 AI lỗi/micro không dùng được, T09 dự kiến ít chờ, T10 tình huống cần hỗ trợ khẩn. Trong app không có nút nào dẫn tới các tính năng này.

## 4. Danh sách màn hình

S00 Trang bắt đầu (có trạng thái trống, bản đang dở, lịch đang xử lý) · S01 Hình thức khám (1/6) · S02 Người khám, S02a Thêm người khám (2/6) · S03a Nơi khám, S03b Chuyên khoa có tìm kiếm, S03c Bác sĩ (3/6) · S04 Ngày giờ (4/6) · S05 Kiểm tra (5/6) · S06 Thanh toán, đang xử lý, lỗi, đang kiểm tra (6/6) · S07 Kết quả · S08 Danh sách và chi tiết lịch · Trợ giúp (mô phỏng).

Trạng thái có sẵn: đang tải (nơi khám, giờ, kiểm tra lại trước thanh toán), trống (tìm khoa không thấy, ngày hết lịch, chưa có lịch hẹn), lỗi nhập (form, chưa chọn), lỗi mạng khi tải giờ, hết chỗ.

## 5. Ghi chú thiết kế

- **Màu:** palette PRD. Tỷ lệ tương phản đã tính bằng công thức WCAG: chữ chính/nền 13.4:1; chữ phụ/trắng 7.6:1; màu hành động/trắng 5.5:1; chữ trên nút chính 5.5:1; các hộp cảnh báo, lỗi, thành công đều trên 7.7:1; chữ ô hết chỗ 4.8:1; viền thẻ lựa chọn 3.4:1. Chỉ một giao diện sáng.
- **Chữ:** 1px CSS ≈ 1dp/sp trên Android ở zoom 100%. Thân 18px, phụ 16px, tiêu đề 26px, nhãn nút 18px. “Chữ 200%” nhân đôi toàn bộ cỡ chữ trong app.
- **Vùng chạm:** nút chính cao 56px, mọi nút ≥ 48 × 48px, khoảng cách 8–16px.
- **Không chỉ dùng màu:** đã chọn có dấu ✓ và chữ “Đã chọn”; hết chỗ có gạch chéo, gạch ngang và chữ “Hết chỗ”; lỗi có biểu tượng “!” và chữ ngay cạnh trường.
- **Giữ / xóa khi sửa (theo PRD mục 6):** đổi hình thức thì giữ người khám, chỉ xóa nơi khám trở về sau nếu nơi đó không nhận hình thức mới. Đổi người khám thì xóa ghi chú lý do khám, kiểm tra tuổi với khoa. Đổi nơi khám thì giữ khoa nếu nơi mới có, luôn chọn lại bác sĩ và giờ. Đổi khoa thì chọn lại bác sĩ và giờ. Đổi bác sĩ thì giữ giờ nếu còn chỗ. Mỗi lần đều có thông báo nói rõ mục nào phải chọn lại.
- **Giả định BHYT/phí/thanh toán:** tất cả cơ sở, bác sĩ, phí, mã lịch, mã giao dịch, QR đều giả. BHYT: 0đ đặt lịch, quyền lợi do cơ sở xác nhận, chỉ trả tại viện. Dịch vụ: An Bình 250.000đ, Sông Xanh 500.000đ (bắt buộc trả trước), Hòa Lạc 180.000đ. Trả tại viện coi như lịch được xác nhận ngay; khi triển khai thật vẫn cần backend xác nhận.
- Không có tính năng đăng nhập/OTP; giả định đã đăng nhập bằng tài khoản Phạm Văn Hòa (sinh 1966).

## 6. Đã tự kiểm tra và hạn chế

Đã chạy tự động bằng trình duyệt Chromium (Playwright) ở 360 × 800 và 412 × 915: đi hết T01, T02, T03 (cả hai nhánh nơi khám, đổi người, đổi hình thức), T04, T05a, T05b, T06, form thêm người khám (lỗi trống, ngày sinh sai, giữ dữ liệu khi quay lại), lỗi mạng khi tải giờ và chế độ chữ 200%. Không có lỗi JavaScript, không tràn ngang, không có chữ bị cắt. Ảnh xem trước nằm trong thư mục `screenshots/`.

Chưa kiểm tra: TalkBack/VoiceOver, thiết bị Android thật, bàn phím ảo thật, cỡ chữ hệ thống của điện thoại (chỉ mô phỏng bằng nút “Chữ 200%”), và chưa thử với người dùng thật. Nội dung mô tả khoa là minh họa, chưa được chuyên môn duyệt.

## 7. Vòng 2 (khung app kiểu MyVinmec + Hướng A)

- Thêm header màu thương hiệu và thanh điều hướng đáy 5 mục: Trang chủ, Hồ sơ, Đặt lịch (nút giữa), Thông báo, Tài khoản. Thanh đáy ẩn khi vào luồng đặt lịch.
- Áp Hướng A: ô icon có nền màu, thẻ bo 20, nút dạng viên thuốc, ô giờ đổi hình khi chọn, trang Kiểm tra nhóm theo 4 phần, kết quả dạng vé khám có QR minh họa.
- Hồ sơ, Thông báo, Tài khoản là trang tối giản, chỉ để bấm thử khung.
- Ở chế độ chữ 200%, header cuộn theo nội dung, nút chính vẫn ghim ở đáy.
- Nhãn thanh đáy dùng 14px và chỉ phóng tối đa 1.4 lần. Đây là chỗ lệch PRD duy nhất, cần duyệt.
- Bản vòng 1 giữ lại tại (bản vòng 1 không đưa vào repo) để so sánh. Định hướng dựng khung Flutter nằm trong `HUONG-DAN-FLUTTER.md`.
- Đã chạy lại tự động T01–T06, 4 tab và chữ 200%: không có lỗi script, không tràn ngang.

## 8. Vòng 3 (tối giản chữ)

Theo yêu cầu của chủ dự án ngày 2026-10-14: bỏ mọi nhãn minh họa trong app vì tài liệu công bố sẽ nêu rõ dữ liệu là giả lập. Điều này thay cho yêu cầu nhãn “Bản thử nghiệm · dữ liệu minh họa” trong brief và PRD mục 8.

- Đã bỏ: nhãn bản thử, “(giả định)”, “(giả lập)”, “(mẫu)”, “minh họa”, “(bản thân)”, các câu dẫn dưới tiêu đề, chú thích cuối trang, chú giải ô giờ, chữ “Còn chỗ” trên từng ô giờ và chữ “Đã chọn” hiển thị (vẫn còn cho trình đọc màn hình).
- Progressive disclosure: ghi chú cho bác sĩ ẩn sau nút “+ Thêm ghi chú cho bác sĩ”; chi tiết phí và quyền lợi BHYT ẩn sau biểu tượng ⓘ; “Chưa biết chọn khoa?” và Trợ giúp chuyển thành câu hỏi bấm để mở.
- Visual metaphor: ô icon cho hình thức, nơi khám, thanh toán; chữ viết tắt tên cho người khám và bác sĩ; ô giờ hết chỗ có gạch chéo và gạch ngang; ô đã chọn đổi màu, đổi hình và có dấu ✓.
- Giữ lại vì ảnh hưởng an toàn hoặc tiền: “Bạn chưa bị trừ tiền”, “Vui lòng không thanh toán lại”, trạng thái chờ xác nhận, lỗi ngay cạnh trường, thông báo khi phải chọn lại sau khi sửa (đã rút còn một dòng).
- Địa chỉ cơ sở đổi sang tên tự nhiên, vẫn là dữ liệu giả.
- Bảng người duyệt vẫn giữ vì nằm ngoài app.
