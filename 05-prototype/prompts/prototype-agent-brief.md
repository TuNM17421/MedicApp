# Prompt bàn giao — Prototype tương tác vòng 1

Sao chép nội dung trong khối dưới đây sang agent dựng prototype. Đây là yêu cầu thiết kế và mô phỏng tương tác; chưa áp dụng vào Flutter.

```text
Bạn là product designer và prototyper cho dự án MedicApp. Hãy dựng một prototype tương tác tiếng Việt để tôi trực tiếp bấm thử và duyệt trước khi phát triển Flutter. Hãy thực hiện việc dựng prototype, không chỉ đưa ra kế hoạch hoặc ảnh tĩnh.

TÀI LIỆU ĐẦU VÀO
Repository: https://github.com/TuNM17421/MedicApp
Đọc trước:
1. 05-prototype/prd-smart-scheduling.md
2. 04-best-practice/README.md
3. README.md
Nếu không đọc được repository, yêu cầu tôi cung cấp hai tài liệu đầu; không tự nhận đã đọc. PRD là nguồn chi tiết; phạm vi vòng 1 trong prompt này ưu tiên luồng cơ bản P0. Các quy tắc an toàn, quyền riêng tư, BHYT và thanh toán của PRD vẫn áp dụng.

BỐI CẢNH VÀ MỤC TIÊU
Theo tóm tắt phỏng vấn do chủ dự án cung cấp, một số người trên 50–60 tuổi thấy đặt khám qua app khó, nhiều bước và thường nhờ con cái hoặc nhân viên bệnh viện thao tác. Chưa có log để coi đây là kết luận nghiên cứu đã được kiểm chứng. Thiết kế cần giúp họ tự đặt khám, biết đang ở bước nào và dễ sửa lựa chọn. Đồng thời hỗ trợ con cái đặt cho người thân.

Ưu tiên sự rõ ràng và khả năng hoàn thành, không chỉ giảm số màn hình. Hướng giao diện tối giản lấy cảm hứng từ MyTherapy theo mong muốn của chủ dự án; tham khảo tác vụ đặt khám của MyVinmec/Bạch Mai Care, không sao chép thương hiệu hoặc tuyên bố đã tái tạo đúng giao diện hiện hành.

GIỚI HẠN BẮT BUỘC
- Không chỉnh sửa bất cứ file nào trong 05-prototype/flutter_app/; không tạo tính năng Flutter/Dart, không cài lại SDK hoặc thay đổi script môi trường.
- Chỉ dựng prototype và tài liệu bàn giao trong một khu vực riêng. Nếu làm trong repo, đặt tại 05-prototype/interactive-prototype/.
- Ưu tiên một prototype web HTML/CSS/JavaScript có thể mở cục bộ, ít phụ thuộc. Có thể chọn công cụ prototype khác nếu cho phép bấm thử đủ luồng; nêu cách mở rõ ràng. Không cần backend.
- Không gọi AI, micro, API bệnh viện, thanh toán hoặc số điện thoại thật. Không thu thập dữ liệu cá nhân thật, không tạo tài khoản hoặc giao dịch thật.
- Không tự commit/push, publish công khai hoặc thay đổi remote. Bàn giao bản xem trước để tôi duyệt.
- Không sửa PRD gốc để hợp thức hóa phần chưa làm; ghi giả định và giới hạn riêng.

PHẠM VI VÒNG 1 — LUỒNG CƠ BẢN
Dựng luồng chính theo đúng thứ tự:
Trang bắt đầu → Hình thức khám → Người khám → Nơi khám/chuyên khoa/bác sĩ → Ngày giờ → Kiểm tra thông tin → Thanh toán → Kết quả và xem lại lịch hẹn.

Chi tiết:
1. Trang bắt đầu: CTA chính “Đặt lịch khám”, hành động phụ “Xem lịch hẹn”. Không thêm newsfeed, quảng cáo, chatbot hoặc dashboard phức tạp.
2. Hình thức: “Khám BHYT” và “Khám dịch vụ (tự chi trả)”. Không tự mặc định hình thức phát sinh phí. Không khẳng định quyền lợi BHYT đã được duyệt.
3. Người khám: hồ sơ bản thân và người thân giả định; chọn người hoặc thêm hồ sơ minh họa. Luôn nhận biết rõ đang đặt cho ai. Giả định đã đăng nhập, không thêm onboarding/OTP vào luồng chính.
4. Nơi khám/khoa: chọn cơ sở rồi chuyên khoa; có tìm kiếm. Có thể tách thành các tiểu màn hình trong cùng một bước. Dùng tên cơ sở/bác sĩ giả định được ghi rõ. Mô phỏng một nơi hỗ trợ và một nơi không hỗ trợ hình thức đã chọn; không tự đổi BHYT sang dịch vụ.
5. Bác sĩ: không bắt buộc biết tên bác sĩ; có lựa chọn bác sĩ còn lịch phù hợp và tùy chọn chọn đích danh. Không quảng cáo bác sĩ “tốt nhất”.
6. Ngày giờ: ngày dễ đọc, khung giờ Sáng/Chiều, phân biệt còn chỗ/hết chỗ/đã chọn bằng chữ và dấu hiệu ngoài màu. Người dùng tự xác nhận giờ.
7. Kiểm tra: tóm tắt người khám, hình thức, nơi/địa chỉ, khoa, bác sĩ hoặc trạng thái chưa phân công, ngày giờ, liên hệ và phí minh họa. Có “Sửa” tại từng nhóm, quay về đúng bước rồi trở lại kiểm tra.
8. Thanh toán: mô phỏng phương thức và số tiền; có trả tại viện khi kịch bản cho phép. Phân biệt thanh toán thành công với lịch khám đã được xác nhận.
9. Kết quả: chỉ nói đặt lịch thành công khi có mã lịch mẫu được xác nhận; thể hiện đã/chưa trả tiền, thông tin lịch và việc cần làm tiếp theo. Có thể mở lại từ danh sách lịch hẹn.

Hiển thị “Bước X/6” theo PRD: hình thức, người khám, nơi/khoa/bác sĩ, ngày giờ, kiểm tra, thanh toán. Các tiểu màn hình chọn cơ sở/khoa/bác sĩ vẫn thuộc bước 3/6. Trang bắt đầu và kết quả không thêm vào số bước.

QUAY LẠI VÀ PHỤC HỒI
- Giữ dữ liệu còn hợp lệ khi quay lại hoặc sửa. Nếu đổi cơ sở/khoa/ngày làm giờ cũ không còn hợp lệ, giải thích và yêu cầu chọn lại; không xóa toàn bộ hồ sơ.
- Đổi người khám không được mang theo triệu chứng hay gợi ý của người trước.
- Dựng tối thiểu T01–T06 trong PRD: đặt dịch vụ; BHYT cho người thân; sửa thông tin; giờ vừa hết; thanh toán lỗi/đang xử lý; đã trả tiền nhưng lịch chưa xác nhận.
- Mất kết nối sau thanh toán phải cho kiểm tra trạng thái, không yêu cầu trả lại ngay hoặc báo thành công giả. Nút đang xử lý không cho tạo nhiều giao dịch/lịch do bấm lặp.
- Có trạng thái tải, trống, lỗi nhập và hết lịch tại các bước phù hợp, với hành động phục hồi rõ.
- Có bộ chọn kịch bản demo riêng cho người duyệt, tách khỏi giao diện chính. Các trạng thái cần tái hiện được, không dựa vào lỗi ngẫu nhiên.

SMART SCHEDULING Ở VÒNG NÀY
Chưa cần dựng nhánh gợi ý chuyên khoa bằng AI, nhận giọng nói hoặc dự báo giờ ít chờ. T07–T10 được ghi là hoãn, không báo đã hoàn thành. Nếu muốn thể hiện vị trí mở rộng, chỉ dùng ghi chú trong tài liệu thiết kế; không đặt CTA trông có thể dùng nhưng bấm không có tác dụng trong luồng chính.
Luồng cơ bản phải hoàn thành độc lập với AI. Không tự ánh xạ “đau đầu kèm buồn nôn” sang một khoa, không bịa số phút chờ hoặc nhãn “vắng nhất”. Trợ giúp thường trong prototype là mô phỏng, không giả làm dịch vụ cấp cứu.

YÊU CẦU GIAO DIỆN
- Một cột, ít trang trí, nhiều khoảng thở, một hành động chính trên mỗi màn hình. Giữ nút quay lại và trợ giúp dễ tìm, không làm mất tiến trình.
- Nền #F7FAF8, bề mặt trắng, chữ chính #16302C, chữ phụ #4B5563, màu hành động #0F766E. Đây là palette đề xuất, không phải màu thương hiệu được xác minh.
- Thân bài mục tiêu 18sp tương đương trên prototype web, phụ không dưới 16; tiêu đề 24–28; nút chính cao ít nhất 56dp, vùng chạm ít nhất 48 × 48dp. Ghi rõ cách quy đổi nếu dùng công cụ web.
- Kiểm tra trên viewport 360 × 800 và 412 × 915, thử tăng chữ 200%; không cắt nội dung hoặc che CTA khi mở bàn phím. Kiểm tra tương phản theo PRD, không tự báo đạt khi chưa đo.
- Dùng từ dễ hiểu: “Người khám”, “Nơi khám”, “Chọn giờ”, “Sửa”. Icon phải có nhãn; lỗi ngay cạnh trường và hướng dẫn cách sửa. Không chỉ dùng toast hoặc màu cho thông tin quan trọng.
- Duy trì nhãn “Bản thử nghiệm · dữ liệu minh họa”. Mọi hồ sơ, bác sĩ, cơ sở, phí, QR và giao dịch đều giả định; QR không có khả năng thanh toán thật.

ĐẦU RA CẦN BÀN GIAO
1. Link hoặc file prototype tương tác có thể mở, kèm hướng dẫn chạy ngắn và dữ liệu được reset thế nào.
2. Danh sách màn hình và bảng mapping T01–T06 đến cách mở kịch bản demo; liệt kê T07–T10 là chưa làm ở vòng này.
3. Ghi chú thiết kế: chữ/màu/vùng chạm, xử lý khi tăng chữ, lựa chọn được giữ hoặc reset, các giả định BHYT/phí/thanh toán.
4. Kết quả bạn đã tự kiểm tra và hạn chế còn lại. Nếu chưa kiểm tra TalkBack, thiết bị thật hoặc người dùng thật, ghi rõ.
5. Ảnh xem trước các màn hình chính nếu công cụ cho phép, nhưng ảnh không thay thế prototype bấm được.

Trước khi bàn giao, tự đi hết T01–T06, kiểm tra quay lại/sửa, tính nhất quán thông tin, trạng thái thanh toán và các điểm thoát lỗi. Không để CTA chính dẫn vào ngõ cụt. Không bịa log phỏng vấn, kết quả thử nghiệm hoặc tuyên bố giảm thời gian chờ. Khi hoàn tất, dừng ở bước tôi duyệt prototype; chưa áp dụng vào Flutter.
```
