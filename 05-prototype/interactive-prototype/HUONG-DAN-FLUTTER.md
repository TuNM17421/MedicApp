# Định hướng dựng khung app Flutter cho MedicApp

Ngày 2026-10-14. Mục tiêu: dựng khung một lần (header, thanh điều hướng đáy, theme, điều hướng, dữ liệu) để sau này thêm Dashboard và tính năng mới mà không phải migrate. Bố cục bám theo mẫu MyVinmec bạn gửi, giao diện theo Hướng A đã duyệt. Bản bấm thử tương ứng: `index.html` trong cùng thư mục.

> Tôi chưa xem được source `flutter_app/` vì thư mục này không có trong repo. Vì vậy tôi chưa biết phiên bản Flutter và các gói đang dùng. Các gói gợi ý dưới đây (go_router, flutter_riverpod) cần kiểm tra tương thích trước khi cài.

## 1. Khung màn hình: 3 loại header, 2 loại đáy

| Vùng | Dùng ở | Nội dung |
| --- | --- | --- |
| `BrandHeader` | Trang chủ | Tên app, câu giới thiệu, nút “Trợ giúp” có chữ. Dải màu thương hiệu kéo xuống, thẻ “Đặt lịch khám” nổi lên trên dải như mẫu MyVinmec |
| `PageHeader` | Hồ sơ, Thông báo, Tài khoản, Lịch hẹn | Tiêu đề trang, “Quay lại” khi là trang con, “Trợ giúp” |
| `FlowHeader` | 6 bước đặt lịch | “Quay lại”, “Trợ giúp”, “Bước X/6”, thanh tiến trình, chip người khám |
| `AppBottomNav` | Các màn hình cấp cao (4 tab) | Trang chủ · Hồ sơ · **Đặt lịch** (nút tròn nổi ở giữa) · Thông báo · Tài khoản |
| `PrimaryActionBar` | Trong luồng đặt lịch | Một nút chính, nhãn cụ thể (“Tiếp tục: Chọn ngày giờ”) |

Quy tắc quan trọng: **vào luồng đặt lịch thì ẩn thanh điều hướng đáy** và thay bằng `PrimaryActionBar` (PRD mục 5: tránh rời luồng vô ý). Mẫu MyVinmec chỉ cho thấy trang chủ; trong luồng chúng ta vẫn giữ header màu thương hiệu cho đồng nhất.

## 2. Điều hướng (go_router)

- Dùng `StatefulShellRoute.indexedStack` với 4 nhánh: `/home`, `/profiles`, `/notifications`, `/account`. Mỗi nhánh giữ lịch sử riêng khi đổi tab.
- Nút giữa “Đặt lịch” **không phải một nhánh**. Đây là hành động `context.push('/booking')`. Toàn bộ `/booking/...` khai báo ở navigator gốc (`parentNavigatorKey: rootNavigatorKey`) nên phủ lên thanh đáy.
- Lịch hẹn nằm trong nhánh Trang chủ (`/home/appointments`, `/home/appointments/:id`) nên vẫn thấy thanh đáy. Thông báo mở chi tiết lịch bằng cùng route này, sẵn cho deep link sau này.
- Luồng đặt lịch dùng một `ShellRoute` riêng (`BookingFlowShell`) bọc các bước: `type`, `patient`, `patient/new`, `facility`, `department`, `doctor`, `datetime`, `review`, `payment`, `payment/status`, rồi `result/:id`. Shell này giữ `BookingDraft` và vẽ `FlowHeader` một lần.
- Sửa từ trang Kiểm tra: đi tới bước với cờ `edit=true`. Khi bản nháp đủ lại thì quay về `review` (logic `firstMissing` trong prototype).
- Nút Back của Android: dùng `PopScope` trong luồng để Back đi về bước trước, không thoát app hay mất bản nháp.

```dart
final router = GoRouter(navigatorKey: rootKey, initialLocation: '/home', routes: [
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => AppShell(shell: shell), // BottomNav + nút Đặt lịch ở giữa
    branches: [
      StatefulShellBranch(routes: [GoRoute(path: '/home', builder: ..., routes: [
        GoRoute(path: 'appointments', builder: ..., routes: [GoRoute(path: ':id', builder: ...)]),
      ])]),
      StatefulShellBranch(routes: [GoRoute(path: '/profiles', builder: ...)]),
      StatefulShellBranch(routes: [GoRoute(path: '/notifications', builder: ...)]),
      StatefulShellBranch(routes: [GoRoute(path: '/account', builder: ...)]),
    ],
  ),
  ShellRoute( // luồng đặt lịch, phủ lên thanh đáy
    parentNavigatorKey: rootKey,
    builder: (context, state, child) => BookingFlowShell(child: child),
    routes: [GoRoute(path: '/booking/type', builder: ...), /* ...các bước còn lại */],
  ),
]);
```

## 3. Dashboard sau này không phải sửa khung

- Trang chủ là danh sách các khối (`HomeSection`): chào hỏi, thẻ “Đặt lịch khám”, lịch hẹn sắp tới, lối tắt. Dashboard mới chỉ thêm khối vào danh sách này, không đổi header hay thanh đáy.
- Lưới lối tắt kiểu MyVinmec (Lịch hẹn, Đơn thuốc...) là một khối `ShortcutGrid` với dữ liệu cấu hình. Nên giới hạn số ô hiển thị cho nhóm 50–60+ và luôn có nhãn chữ.
- PRD không cho banner quảng cáo hay chatbot tự bật trong trải nghiệm đặt lịch. Nếu Dashboard có banner, chỉ đặt ở Trang chủ, không đặt trong luồng.
- Thêm tab mới thì thêm một nhánh `StatefulShellBranch` và một mục trong `AppBottomNav`. Nên giữ tối đa 5 mục.

## 4. Theme và token (đặt trước, không hard-code)

- `ThemeData(useMaterial3: true)` với màu đặt tường minh: primary `#0F766E`, onPrimary trắng, nền `#F7FAF8`, surface trắng, chữ `#16302C`, chữ phụ `#4B5563`. Không dùng `fromSeed` để tránh màu tự sinh lệch palette đã duyệt.
- `ThemeExtension<AppTokens>` chứa:
  - 4 cặp màu nền/icon cho ô icon (teal, peach, lavender, sky) và 4 màu trạng thái (cảnh báo, lỗi, thành công, thông tin), lấy đúng giá trị trong prototype;
  - bo góc: thẻ 20, vé 24, nút dạng viên thuốc, ô giờ dạng viên thuốc và đổi thành bo 14 khi chọn;
  - khoảng cách 4/8/12/16/20/24 và bóng thẻ nhẹ.
- `TextTheme`: thân 18, phụ 16, tiêu đề 26, tiêu đề mục 20, nhãn nút 18 đậm. Font Be Vietnam Pro đóng gói trong `assets/` để chạy offline, không tải lúc chạy.
- Widget chỉ đọc màu, cỡ chữ và bo góc từ `Theme.of(context)` và `AppTokens`. Khi đổi thương hiệu hay thêm chế độ tối, chỉ sửa một file.

## 5. Widget dùng chung (dựng trước màn hình)

`IconTile` (tone, icon hoặc chữ viết tắt tên) · `ChoiceCard` (icon, tiêu đề, mô tả, đã chọn, lý do không chọn được) · `DateChip` · `SlotChip` (còn chỗ / hết chỗ / đã chọn, có chữ và hoa văn, không chỉ màu) · `StatusBanner` (info/warn/error/ok, có `liveRegion`) · `ReviewSection` (nhóm + nút “Sửa” có nhãn đọc màn hình) · `TicketCard` · `EmptyState` · `LoadingState` · `ErrorState(onRetry)`.

Viết golden test cho từng widget ở bề rộng 360 và 412, với textScale 1.0 và 2.0.

## 6. Chữ lớn và tiếp cận

- Không chặn `textScaler` toàn app. Ngoại lệ duy nhất là nhãn thanh đáy: giới hạn 1.4 lần, dùng cỡ 14 thay vì 16 để 5 nhãn vừa màn 360. Điểm này lệch so với PRD (chữ phụ ≥ 16) và cần bạn duyệt.
- Khi `textScaler > 1.3`, `FlowHeader` cuộn theo nội dung (`SliverAppBar` không ghim) để không chiếm nửa màn hình; nút chính và thanh đáy vẫn ghim. Hàng thông tin ở trang Kiểm tra chuyển sang một cột. Prototype đã mô phỏng điều này ở chế độ “Chữ 200%”.
- `Semantics`: trạng thái đã chọn, nhãn “Sửa người khám” thay cho “Sửa”, thông báo lỗi đọc ngay. Vùng chạm tối thiểu 48 × 48.

## 7. Dữ liệu: đổi từ giả lập sang thật mà không sửa UI

- `BookingDraft` bất biến (`copyWith`) và `BookingRules` viết bằng Dart thuần: `firstMissing`, đổi hình thức, người, nơi, khoa, bác sĩ cùng thông báo kèm theo. Chuyển nguyên logic từ prototype (PRD mục 6) và viết unit test cho từng dòng của bảng.
- Quản lý trạng thái: chọn một thư viện và dùng xuyên suốt. Gợi ý Riverpod, với `bookingDraftProvider` giới hạn trong `BookingFlowShell`.
- Repository dạng interface: `FacilityRepository`, `DoctorRepository`, `SlotRepository` (lấy giờ, kiểm tra lại trước thanh toán), `PaymentRepository` (tạo giao dịch với khóa chống trùng, hỏi trạng thái), `AppointmentRepository`. Bây giờ dùng bản `Mock...` lấy dữ liệu từ prototype; khi có API, thay bằng `Api...` qua provider override hoặc flavor.
- Trạng thái thanh toán và lịch là enum, map 1-1 với màn hình: `processing`, `failed`, `unknown` (mất kết nối), `paidUnconfirmed`, `confirmed`. Khóa chống trùng là id của bản nháp, nên bấm lặp không tạo hai lịch.

## 8. Thư mục (theo tính năng)

```
lib/
  app/          router.dart, app_shell.dart, theme/ (app_theme.dart, app_tokens.dart)
  core/         widgets/ (choice_card, icon_tile, slot_chip, status_banner, ticket_card…), utils/
  features/
    home/           presentation/ (sections/)
    booking/        domain/ (booking_draft, booking_rules), data/ (repositories, mock/), presentation/ (steps/)
    appointments/   profiles/   notifications/   account/
  l10n/         app_vi.arb  (chuỗi tiếng Việt qua flutter gen-l10n ngay từ đầu)
```

## 9. Thứ tự làm đề xuất

1. Theme, token, font và ARB.
2. `AppShell` + router + 4 tab rỗng + nút “Đặt lịch” mở luồng trống.
3. Widget dùng chung + golden test.
4. `BookingDraft`, `BookingRules`, repository giả lập + unit test.
5. Sáu bước đặt lịch, rồi Kết quả, Lịch hẹn, Thông báo.

## 10. Lưu ý thương hiệu

Chỉ mượn bố cục của MyVinmec (header màu, thẻ nổi, thanh đáy có nút giữa). Không dùng logo, khẩu hiệu, banner hay hình ảnh của Vinmec. Tên “MedicApp” và câu “Đặt khám dễ dàng cho cả nhà” là tạm thời.
