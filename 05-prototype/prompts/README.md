# Prompt log

**Prompt bàn giao có thể sao chép:** [Prototype tương tác vòng 1](prototype-agent-brief.md).

## AI-001 — Khởi tạo cấu trúc bàn giao

- Yêu cầu: “Check và dựng lại structure project cho tôi xem”, dựa trên bảng cấu trúc bàn giao người dùng cung cấp.
- Đầu vào: Tên thư mục và nội dung cần nộp cho bài nghiên cứu MyVinmec.
- Đầu ra: Khung thư mục, README, biểu mẫu, dàn ý slide và `.gitignore`.
- Công cụ: Codex.
- Kiểm tra: Kiểm tra cấu trúc và liên kết nội bộ; chưa kiểm chứng nội dung nghiên cứu vì chưa có dữ liệu.

## AI-002 — Thiết lập Flutter Android

- Ngày: 2026-10-14.
- Prompt: “Tiếp theo cài môi trường Flutter cho Android theo cách dễ gỡ như đã đề xuất, rồi khởi tạo app trong 05-prototype/flutter_app giúp tôi. Kiểm tra xem terminal đã có gh chưa nếu chưa có thì cho phép install về và tôi sẽ login”.
- Công cụ: Codex, PowerShell, Flutter CLI.
- Đầu ra: Script môi trường portable trong `scripts/`, manifest phiên bản/checksum, Flutter Android starter sinh từ template chính thức, tài liệu chạy và gỡ môi trường.
- Phạm vi: Khởi tạo công cụ và app mẫu; chưa tạo dữ liệu nghiên cứu hoặc tính năng y tế. Người dùng tự đăng nhập GitHub.
- Kiểm chứng: Xem [kết quả thiết lập](../../scripts/verification.md).

## AI-003 — PRD Smart Scheduling, chưa code

- Ngày: 2026-10-14.
- Yêu cầu tóm tắt: Dựa trên khó khăn đặt khám của người 50–60+ do chủ dự án cung cấp, viết PRD cho một app đặt khám tối giản theo hướng MyTherapy, luồng cơ bản tham chiếu MyVinmec/Bạch Mai Care; ghi nhận best practice. Luồng cơ bản là nền và fallback cho gợi ý khoa từ triệu chứng/giọng nói và gợi ý giờ ít chờ. Chủ dự án sẽ dùng agent khác dựng prototype để duyệt trước khi áp dụng vào Flutter.
- Đầu vào: Hội thoại và nguồn công khai S1–S4 trong `04-best-practice/README.md`; không có log phỏng vấn gốc hoặc dữ liệu bệnh viện.
- Đầu ra: `05-prototype/prd-smart-scheduling.md`, cập nhật best practice, README và prompt log.
- Công cụ: Codex và tìm kiếm web; không sửa code Flutter, không triển khai AI/backend, không commit/push.
- Điều chỉnh cần duyệt: Dùng ngôn ngữ gợi ý có giới hạn thay cho cam kết đúng khoa/giờ vắng nhất; các ước tính và giao dịch chỉ mô phỏng khi chưa có dữ liệu vận hành. Quy tắc BHYT và luồng khẩn cần đơn vị chuyên môn xác nhận trước triển khai thật.
- Kiểm chứng: Mở nguồn chính thức, phân biệt thông tin công bố với suy luận thiết kế; kiểm tra liên kết Markdown nội bộ. Chưa kiểm thử app tham chiếu, hiệu quả với người dùng hoặc tính phù hợp lâm sàng.

## AI-004 — Bàn giao tài liệu và prompt prototype vòng 1

- Ngày: 2026-10-14.
- Yêu cầu: Đẩy tài liệu cơ bản lên Git trước, sau đó viết prompt cho agent khác dựng prototype tương tác theo PRD; ưu tiên luồng đặt lịch cơ bản và giao diện tối giản; chưa sửa code Flutter.
- Đầu ra: Bản tài liệu đầu tiên trên nhánh `main`; prompt tại `prototype-agent-brief.md` và liên kết từ README.
- Phạm vi prompt: P0, các kịch bản T01–T06; nhánh Smart Scheduling T07–T10 hoãn sang vòng sau. Chỉ sử dụng dữ liệu và thanh toán giả lập.
- Kiểm tra: Giới hạn file trong commit tài liệu, kiểm tra liên kết nội bộ và tính nhất quán của prompt với phạm vi vòng 1. Chưa dựng hoặc thử nghiệm prototype.

## AI-005 — Nền giao diện Flutter bước 1

- Ngày: 2026-10-14.
- Yêu cầu: “Bắt đầu impl bước 1 nhé: dựng theme, font Be Vietnam Pro, icon và các widget dùng chung theo bố cục prototype đã duyệt. Chưa làm luồng đặt lịch vội.”
- Đầu vào: PRD, bộ package đã cài, HTML/ảnh và hướng dẫn trên nhánh `prototype/interactive-booking` tại `89c4fcd`; chỉ coi bố cục đã được duyệt.
- Đầu ra: Theme/tokens, font offline có giấy phép, icon Lucide, widget dùng chung, màn hình xem trước, test và tài liệu `flutter_app/DESIGN-SYSTEM.md`.
- Kiểm tra: Analyze, widget tests trên hai kích thước và hai mức chữ, ảnh render có font/icon và build APK debug. Chưa có thử nghiệm thiết bị/TalkBack hoặc người dùng thật.
- Giới hạn: Không có luồng đặt khám, backend hoặc giao dịch; không commit/push trong bước này.

## AI-006 — Shell điều hướng và Riverpod bước 2

- Ngày: 2026-10-14.
- Yêu cầu: “Tiếp tục impl bước 2 nhé: dựng khung điều hướng các tab bằng go_router và quản lý trạng thái bằng Riverpod theo bố cục prototype. Chưa làm luồng đặt lịch vội.”
- Đầu ra: Shell bốn nhánh độc lập, hành động Đặt lịch trên navigator gốc, các trang con, trạng thái hồ sơ/thông báo trong phiên, badge và tài liệu `flutter_app/NAVIGATION.md`.
- Kiểm tra: Analyze, test trạng thái/điều hướng và golden, Back mô phỏng, hai kích thước ở hai cỡ chữ, build APK debug. Chưa kiểm tra thiết bị/TalkBack hoặc người dùng thật.
- Giới hạn: Dữ liệu giả định; chưa có đăng nhập, API, lưu bền, bản nháp hoặc luồng đặt khám. Không commit/push trong bước này.

## AI-007 — Tinh gọn footer

- Ngày: 2026-10-14.
- Yêu cầu: Bỏ chữ dưới icon hoặc thiết kế lại footer đang thiếu gọn gàng.
- Thay đổi: Footer một hàng chỉ icon, nút Đặt lịch nổi giữa, nền bo góc, highlight tab, giữ badge, semantics và tooltip tên mục.
- Kiểm tra: 27 test và ảnh render ở chữ 100%/200%; cập nhật bộ tìm phần tử test theo key ổn định thay vì nhãn hiển thị.
- Phạm vi: Không thay đổi route, Riverpod hoặc luồng đặt lịch.

## Mẫu ghi nhận tiếp theo

- Mã, ngày, người sử dụng, công cụ/model nếu biết.
- Prompt nguyên văn đã loại bỏ dữ liệu nhạy cảm và đầu vào tham chiếu.
- File/kết quả được tạo.
- Phần chấp nhận, chỉnh sửa hoặc loại bỏ; người kiểm tra và cách kiểm chứng.

## AI-008 — Đặt lịch cơ bản bước 3

- Ngày: 2026-10-14.
- Yêu cầu: “Ok, tiếp tục impl bước 3: luồng đặt lịch cơ bản từ chọn hình thức khám, người khám, nơi/khoa/bác sĩ, ngày giờ đến kiểm tra và thanh toán giả lập. Giữ footer mới, chưa làm Smart Scheduling nhé.”
- Đầu ra: Luồng sáu bước, thêm người khám, sửa thông tin và hủy lựa chọn phụ thuộc, repository mô phỏng, xử lý giờ hết chỗ, bốn trạng thái thanh toán, danh sách/chi tiết lịch hẹn. Tài liệu `flutter_app/BOOKING.md`.
- Kiểm tra: Unit/widget/golden tests; luồng BHYT ở chữ 200%. Chưa thử trên thiết bị/TalkBack hoặc người dùng thật.
- Giới hạn: Dữ liệu hoàn toàn giả định, bộ nhớ trong phiên, chưa kết nối bệnh viện hoặc thanh toán thật, chưa Smart Scheduling. Giữ footer chỉ icon. Không commit/push trong bước này.

## AI-009 — Hoàn thiện UI/UX bước 4

- Ngày: 2026-10-14.
- Yêu cầu: “Tiếp tục impl bước 4 nhé: hoàn thiện UI/UX cho luồng đặt lịch với animation nhẹ, loading skeleton và hỗ trợ cỡ chữ lớn. Giữ footer hiện tại, chưa làm Smart Scheduling.”
- Đầu ra: Hiệu ứng vào bước 180 ms bằng flutter_animate, skeleton giờ khám bằng skeletonizer, chính sách giảm chuyển động, ô chọn không nhảy chiều cao, tự cuộn tới lỗi, semantics/loading và cải thiện form/bàn phím/safe area. Tài liệu `flutter_app/UI-UX.md`.
- Kiểm tra: Test animation và skeleton, semantics mô phỏng, luồng ở chữ 250% trên màn hình nhỏ và chữ 200% ở màn hình ngang, form với bàn phím/safe area giả lập, ảnh render giờ và skeleton. Bộ kiểm tra bước trước tiếp tục chạy.
- Giới hạn: Chưa thử điện thoại/TalkBack/người dùng thật. Dữ liệu, thanh toán vẫn giả lập; footer giữ nguyên; chưa Smart Scheduling; không commit/push trong bước này.

## AI-010 — Nghiên cứu Smart Scheduling và STT

- Ngày: 2026-10-14.
- Yêu cầu: Bắt đầu nghiên cứu dịch vụ Smart Scheduling có STT; dùng OpenAI, chọn model phù hợp và giải thích chỗ điền API key để test điện thoại.
- Đầu ra: `smart-scheduling-research.md`, `backend/.env.example`, hướng dẫn cấu hình backend. Đối chiếu tài liệu OpenAI hiện tại, Flutter, Android và package chính thức.
- Quyết định đề xuất: GPT-6.1 Sol cho gợi ý có cấu trúc, GPT-Transcribe cho STT bản ghi; backend giữ key và app nối qua USB port reverse khi triển khai. Giờ ít chờ cần dữ liệu vận hành, chưa suy ra từ lịch trống.
- Giới hạn: Chỉ nghiên cứu và mẫu cấu hình; chưa backend chạy được, chưa sửa Flutter, chưa cài package, chưa có API key hoặc gọi OpenAI, chưa đánh giá chất lượng tiếng Việt/lâm sàng. Không tạo log người dùng thật hoặc commit/push.

## AI-011 — Chuyển Smart Scheduling sang hội thoại streaming

- Ngày: 2026-10-14.
- Yêu cầu cập nhật: Bấm ghi → nói → chữ streaming; sửa bằng nói tiếp; tự gửi khi hết lượt; hỏi lại thông tin thiếu bằng giọng nói/lựa chọn/vị trí; đề xuất đủ khoa, bác sĩ và giờ; sửa tổng quan rồi xác nhận để vào thanh toán hiện có.
- Đầu ra: `smart-scheduling-conversation.md` là đặc tả v2; đánh dấu thay thế luồng cũ trong PRD/research; đổi mẫu STT sang `gpt-live-transcribe`. API key vẫn ở backend.
- Nguồn kiểm tra: Realtime transcription, VAD và trang model chính thức OpenAI. Model live cần VAD tại ứng dụng, không cấu hình server_vad/semantic_vad cho model này.
- Quy tắc: Không duyệt transcript riêng, không giới hạn cứng hai câu nếu còn thiếu thông tin, có một xác nhận proposal trước thanh toán, chỉ dùng bác sĩ/slot trong catalog, loại phản hồi cũ và không tự ghi đè sửa tay.
- Giới hạn: Tài liệu và mẫu cấu hình; chưa code dịch vụ/Flutter, chưa gọi API hoặc cài package; chưa có đo VAD/audio/người dùng thật. Không commit/push.

## AI-012 — Bàn giao code và PRD triển khai Smart Scheduling

- Ngày: 2026-10-15.
- Yêu cầu: Tạm thời đẩy code hiện tại lên remote với nhánh riêng, rồi viết PRD triển khai Smart Scheduling và đẩy PRD lên remote. Yêu cầu trước đó chọn model hỏi đáp rẻ để test được giữ lại.
- Bàn giao code: Nhánh `codex/booking-ui-smart-scheduling-prd`, commit `a6e0e9a`; Flutter bước 1–4, tests, font và script môi trường portable. Analyze sạch và 52 test pass trước push. Không đưa SDK/cache/APK/.env vào Git.
- Bàn giao tài liệu: `prd-smart-scheduling-implementation.md`, liên kết từ README/PRD cũ; mẫu backend đổi sang `gpt-6-luna` / reasoning `low`, STT giữ `gpt-live-transcribe`. Tài liệu nêu rõ luồng hỏi-sửa-đề xuất-xác nhận-thanh toán, contract, version, giới hạn chi phí, fallback và tiêu chí nghiệm thu.
- Giới hạn: Chưa triển khai Smart Scheduling hoặc gọi OpenAI; không nâng model đắt tự động. Mới có mẫu cấu hình backend, chưa có server chạy được. Không tạo log thử hoặc số liệu lâm sàng giả.

## AI-013 — Sửa lỗi Quay lại và triển khai Smart Scheduling

- Ngày: 2026-10-15.
- Yêu cầu: Sửa lỗi "Quay lại", sau đó đọc PRD Smart Scheduling và triển khai.
- Sửa lỗi: Khi sửa Hình thức khám từ màn xác nhận, Quay lại không còn đóng luồng mà trở về bước còn thiếu hoặc màn xác nhận; thêm 3 test.
- Triển khai: Backend Node local (`05-prototype/backend`, Responses API `gpt-6-luna`, Realtime transcription `gpt-live-transcribe`, chế độ mô phỏng khi không có key, 28 test) và màn Đặt lịch thông minh trong app (giọng nói, nhập tay, lựa chọn nhanh, đề xuất có Sửa/Hoàn tác, bàn giao vào bước Thanh toán, 22 test).
- Giới hạn: Chưa build APK, chưa thử trên OPPO, chưa gọi OpenAI bằng key thật, chưa làm "Dùng vị trí hiện tại". 8 test ảnh chuẩn cần cập nhật trên Windows. Code và tài liệu do Claude viết; không có log thử người dùng thật.

## AI-014 — Đăng ký, đăng nhập và hồ sơ từ QR CCCD

- Ngày: 2026-10-15 (merge 2026-10-16, PR #2). Công cụ: Claude Code.
- Đầu ra: Màn Chào mừng, tạo tài khoản bằng số điện thoại và mật khẩu, tạo hồ sơ bằng quét QR CCCD hoặc tự nhập, thêm hồ sơ người thân, đăng xuất. Xem [AUTH-CCCD.md](../flutter_app/AUTH-CCCD.md).
- Giới hạn: Đăng nhập giả lập trong bộ nhớ, không có server. Chưa quét bằng camera thật.

## AI-015 — Lưu ý cá nhân hóa trước khám cho 5 bệnh

- Ngày: 2026-10-15 (merge 2026-10-16, PR #3). Công cụ: Claude Code.
- Đầu ra: Mục "Bệnh đang theo dõi" trong hồ sơ; lưu ý có giờ cụ thể cho đái tháo đường, rối loạn mỡ máu, tăng huyết áp, gút, viêm dạ dày. Xem [LUU-Y-TRUOC-KHAM.md](../flutter_app/LUU-Y-TRUOC-KHAM.md).
- Giới hạn: Nội dung tổng hợp từ hướng dẫn công khai có ghi nguồn; cần bác sĩ duyệt trước khi dùng thật.

## AI-016 — Thông báo nhắc khám trên điện thoại

- Ngày: 2026-10-15 (merge 2026-10-16, PR #4). Công cụ: Claude Code.
- Đầu ra: Thông báo cục bộ theo mốc kiêng/nhịn ăn và 2 tiếng trước giờ khám, bố cục mở rộng có nút "Xem hướng dẫn" và "Đã hiểu". Xem [THONG-BAO-NHAC-KHAM.md](../flutter_app/THONG-BAO-NHAC-KHAM.md).
- Giới hạn: Không có máy chủ push.

## AI-017 — Làm đẹp giao diện

- Ngày: 2026-10-15 (merge 2026-10-16, PR #5). Công cụ: Claude Code.
- Đầu ra: Icon và màn mở app, hình minh họa cho màn trống, chuyển trang, lịch tháng ở trang Lịch hẹn; hiệu ứng tắt khi bật giảm chuyển động hoặc trình đọc màn hình. Xem [LAM-DEP-UI.md](../flutter_app/LAM-DEP-UI.md).

## AI-018 — Lưu hồ sơ gia đình trên máy sau khi đồng ý

- Ngày: 2026-10-15 (merge 2026-10-16, PR #6). Công cụ: Claude Code.
- Đầu ra: Màn đồng ý với ô chưa tick sẵn; lưu tài khoản, hồ sơ và phiên trong file mã hóa AES-256-GCM, khóa trong Android Keystore; "Ngừng lưu và xóa khỏi máy". Xem [LUU-TRU-DU-LIEU.md](../flutter_app/LUU-TRU-DU-LIEU.md).
- Căn cứ: Dữ liệu sức khỏe là dữ liệu cá nhân nhạy cảm theo Nghị định 356/2025/NĐ-CP.

## AI-019 — Kết quả khám và đơn thuốc theo mẫu Bộ Y tế

- Ngày: 2026-10-16 (PR #7). Công cụ: Claude Code.
- Đầu vào: Mẫu đơn thuốc Thông tư 18/2018/TT-BYT do chủ dự án cung cấp.
- Đầu ra: Mục "Kết quả khám" với hai cách xem "Dễ đọc" và "Bản đơn thuốc"; web bác sĩ được mô phỏng bằng nút trong app. Xem [DON-THUOC.md](../flutter_app/DON-THUOC.md).

## AI-020 — Nhắc uống thuốc theo đơn (bước 12)

- Ngày: 2026-10-16 (PR #8). Công cụ: Claude Code.
- Đầu ra: Lịch uống tự tạo từ đơn, thông báo có nút Đã uống/Nhắc lại sau 10 phút, nhắc lại sau 30 phút, báo sắp hết thuốc, màn Thuốc hôm nay và lịch sử 4 tuần. Xem [NHAC-THUOC.md](../flutter_app/NHAC-THUOC.md).

## AI-021 — Web bác sĩ, bước 13–18

- Ngày: 2026-10-16 (merge 2026-10-17, PR #9–#14). Công cụ: Claude Code, theo plan triển khai web bác sĩ đã duyệt.
- Đầu ra:
  - Bước 13: package dùng chung [medic_core](../packages/medic_core/README.md), cách tính tuân thủ 30 ngày, cơ sở dữ liệu phòng khám.
  - Bước 14: [web bác sĩ](../doctor_web/README.md) phần xem: hàng chờ, tóm tắt trước khám, tuân thủ, lịch sử.
  - Bước 15: kê đơn, in đơn theo mẫu TT 18, gửi kết quả bằng mã nhận.
  - Bước 16: người bệnh đăng nhập bằng OTP, đồng ý chia sẻ theo từng lượt khám và rút lại được.
  - Bước 17: tóm tắt trước khám từ câu trả lời người bệnh, mỗi câu dẫn về câu gốc; dấu hiệu cần chú ý bắt bằng danh sách cụm từ, không nhờ AI.
  - Bước 18: quản trị tài khoản, nhật ký truy cập, sao lưu, trang số liệu chạy thử; [kế hoạch chạy thử](../docs/ke-hoach-chay-thu.md) và [hồ sơ đánh giá tác động dữ liệu](../docs/danh-gia-tac-dong-du-lieu.md) (bản nháp).
- API: [CLINIC-API.md](../backend/CLINIC-API.md).
- Giới hạn: Chưa gọi OpenAI bằng key thật, chưa có nhà cung cấp SMS, chưa chạy thử với phòng khám thật. Hồ sơ dữ liệu là bản nháp, không phải ý kiến pháp lý.

## AI-022 — Chuông báo uống thuốc

- Ngày: 2026-10-18 (merge 2026-10-19, PR #15). Công cụ: Claude Code.
- Đầu ra: Công tắc "Chuông báo uống thuốc"; sau khi xin quyền báo thức chính xác và hiện trên màn hình khóa, lời nhắc đổ chuông như báo thức đến khi bấm Đã uống hoặc Nhắc lại sau 10 phút. Từ chối quyền thì giữ thông báo thường.

## AI-023 — Bản đồ cơ sở khám

- Ngày: 2026-10-18 (merge 2026-10-19, PR #16). Công cụ: Claude Code.
- Đầu ra: Thẻ "Cơ sở khám gần bạn" mở bản đồ OpenStreetMap; bước "Chọn nơi khám" gợi ý cơ sở gần nhất phù hợp với BHYT và sắp theo khoảng cách. Từ chối quyền vị trí vẫn đặt lịch được.
- Giới hạn: Máy chủ tile của OSM không dành cho lưu lượng production; cần đổi nhà cung cấp tile trả phí khi phát hành.

## AI-024 — Liên kết hai máy cho người thân

- Ngày: 2026-10-18 (merge 2026-10-19, PR #17). Công cụ: Claude Code.
- Đầu ra: Liên kết hồ sơ người thân với máy của chính người đó bằng QR dùng một lần, hết hạn sau 15 phút. Lịch hẹn hiện ở cả hai máy, chuông thuốc chỉ kêu ở máy người uống, người thân được báo khi quá 60 phút chưa ghi liều. Xem [LIEN-KET-HAI-MAY.md](../flutter_app/LIEN-KET-HAI-MAY.md) và [FAMILY-API.md](../backend/FAMILY-API.md).
- Giới hạn: Chưa có thông báo đẩy FCM/APNs; máy người thân chỉ biết lỡ liều khi app đang mở.

## AI-025 — Rà soát tài liệu còn thiếu

- Ngày: 2026-10-19. Công cụ: Claude Code.
- Yêu cầu: "Kiểm tra xem còn những tài liệu nào cần phải hoàn thiện; tôi sẽ cung cấp thông tin để bạn hoàn thiện chúng."
- Đầu ra: Danh sách tài liệu còn trống kèm câu hỏi cho chủ dự án; cập nhật README gốc, README 05-prototype, trạng thái PRD và prompt log AI-014–AI-025 từ mô tả các PR đã merge.
- Đợt 2: Chủ dự án ghi câu trả lời và ảnh dùng thử trong thư mục trên máy. AI dựng ghi chép dùng thử, interview guide, log P1–P4, insight; soạn nháp journey map, need statement, sổ rủi ro, coach plan và dàn ý slide.
- Giới hạn: Không tạo trích dẫn, người tham gia hay số liệu mới. Test-logs, changes.md và hai tài liệu chạy thử để lại vì chưa có thông tin. Ảnh dùng thử được thêm sau khi chủ dự án che tên trong ảnh xác nhận đặt hẹn và đồng ý đẩy lên repo.

## AI-026 — Hoàn thiện tài liệu theo duyệt

- Ngày: 2026-10-19. Công cụ: Claude Code.
- Đầu ra: Gộp nội dung đã duyệt vào tài liệu nghiên cứu; thêm thử "Đặt lịch theo triệu chứng" của MyVinmec; kết quả kiểm thử AI thật và rủi ro R13; mục cấp cứu 115 theo cách hiểu đã thống nhất; coach plan nhịp 6 tuần; deck 10 slide xuất ra `slides.pdf`.

## AI-027 — Kiểm thử lại toàn luồng và gợi ý gọi 115

- Ngày: 2026-10-19. Công cụ: Claude Code.
- Yêu cầu: "Test lại full flow và có sử dụng AI thật cho tôi. Xem có chỗ nào còn vấn đề không? … Và thử check cho tôi việc sử dụng Smart scheduling có hoạt động trong trường hợp khẩn cấp (Gợi ý gọi 115) nếu người dùng nói triệu chứng thuộc dấu hiệu quan trọng không? Nếu chưa có hãy Impl mock một trường hợp như vậy."
- Đầu ra: Smart Scheduling luôn so mô tả với danh sách dấu hiệu cấp cứu tạm trong code trước khi gọi model, AI chỉ bổ sung; màn cấp cứu nêu dấu hiệu, có nút Gọi 115 (chỉ mở màn gọi điện) và nút xem cơ sở gần nhất. Sửa hai lỗi thấy khi chạy lại toàn luồng: lịch hẹn đã qua hiện ở "Lịch hẹn sắp tới", và câu báo hết giờ trống không hiện khi Smart Scheduling hỏi lại thời gian.
- Giới hạn: Danh sách dấu hiệu chưa được chuyên môn duyệt.
