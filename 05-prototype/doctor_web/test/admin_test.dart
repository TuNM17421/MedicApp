import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'doctor_web_test.dart' show pumpApp;
import 'fixtures.dart';

/// Bước 18: accounts and pilot numbers for the admin, the forced password
/// change and the access log.
void main() {
  void go(WidgetTester tester, String location) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);

  testWidgets('quản trị vào trang Tài khoản, không thấy hàng chờ', (
    tester,
  ) async {
    final backend = await pumpApp(tester, backend: FakeBackend(admin: true));
    expect(find.text('Tài khoản'), findsWidgets);
    expect(find.text('BS. Nguyễn Thu Hà'), findsOneWidget);
    expect(find.text('Số liệu'), findsOneWidget);
    expect(find.text('Hàng chờ'), findsNothing);
    expect(backend.calls, isNot(contains('GET /v1/clinic/worklist')));

    // A chart link is no place for the admin.
    go(tester, '/visit/a-p2');
    await tester.pumpAndSettle();
    expect(find.text('Thêm tài khoản'), findsOneWidget);
    expect(backend.calls, isNot(contains('GET /v1/appointments/a-p2/chart')));
  });

  testWidgets('tạo tài khoản: mật khẩu tạm hiện một lần, danh sách cập nhật', (
    tester,
  ) async {
    final backend = await pumpApp(tester, backend: FakeBackend(admin: true));
    await tester.tap(find.text('Thêm tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập họ và tên.'), findsOneWidget);
    expect(find.text('Nhập email hợp lệ.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Họ và tên'),
      'Lê Văn Nam',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email đăng nhập'),
      'bs.nam@anbinh.test',
    );
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('POST /v1/clinic/staff'));
    expect(find.text('Mật khẩu tạm'), findsOneWidget);
    expect(find.text('k7mq-4xr2-9dpt'), findsOneWidget);

    await tester.tap(find.text('Đã ghi lại'));
    await tester.pumpAndSettle();
    expect(find.text('k7mq-4xr2-9dpt'), findsNothing);
    expect(find.text('BS. Lê Văn Nam'), findsOneWidget);
    expect(find.text('Chờ đổi mật khẩu'), findsOneWidget);
    expect(find.textContaining('Chưa đăng nhập'), findsOneWidget);
  });

  testWidgets('khóa tài khoản và đặt lại mật khẩu', (tester) async {
    final backend = await pumpApp(tester, backend: FakeBackend(admin: true));
    // The admin's own row has no actions.
    expect(find.byTooltip('Thao tác với Quản trị An Bình'), findsNothing);

    await tester.tap(find.byTooltip('Thao tác với BS. Nguyễn Thu Hà'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khóa tài khoản').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('bị đăng xuất ngay'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Khóa tài khoản'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('POST /v1/clinic/staff/pr-ha/deactivate'));
    expect(find.text('Đã khóa'), findsOneWidget);

    await tester.tap(find.byTooltip('Thao tác với BS. Nguyễn Thu Hà'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đặt lại mật khẩu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Đặt lại'));
    await tester.pumpAndSettle();
    expect(find.text('z9yx-8wvt-7srq'), findsOneWidget);
  });

  testWidgets('số liệu chạy thử: 4 con số và bảng theo ngày', (tester) async {
    final backend = await pumpApp(tester, backend: FakeBackend(admin: true));
    await tester.tap(find.text('Số liệu'));
    await tester.pumpAndSettle();
    expect(find.text('Số liệu chạy thử'), findsOneWidget);
    expect(backend.calls, contains('GET /v1/clinic/pilot-metrics'));
    expect(find.text('4/8'), findsOneWidget);
    expect(find.text('50%'), findsWidgets);
    expect(find.text('3 giờ'), findsWidgets);
    expect(find.text('1 Đúng · 1 Chưa đúng'), findsOneWidget);
    expect(find.textContaining('1/3 kết quả đã nhận'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('20/10/2026'), findsOneWidget);
    expect(find.text('19/11/2026'), findsOneWidget);

    await tester.tap(find.text('7 ngày'));
    await tester.pumpAndSettle();
    expect(
      backend.calls.where((c) => c == 'GET /v1/clinic/pilot-metrics').length,
      2,
    );
  });

  testWidgets('quản trị tra nhật ký theo mã người bệnh', (tester) async {
    await pumpApp(tester, backend: FakeBackend(admin: true));
    await tester.tap(find.text('Nhật ký'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '999999');
    await tester.tap(find.text('Xem nhật ký'));
    await tester.pumpAndSettle();
    expect(
      find.text('Không có người bệnh mã 999999 ở phòng khám này.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '000482');
    await tester.tap(find.text('Xem nhật ký'));
    await tester.pumpAndSettle();
    expect(find.text('Phạm Thị Lan · Mã 000482'), findsOneWidget);
    expect(find.text('Mở hồ sơ lượt khám'), findsOneWidget);
  });

  testWidgets('bác sĩ không vào được trang quản trị', (tester) async {
    final backend = await pumpApp(tester);
    expect(find.text('Số liệu'), findsNothing);
    go(tester, '/admin/accounts');
    await tester.pumpAndSettle();
    expect(find.text('Hàng chờ 19/11/2026'), findsOneWidget);
    expect(backend.calls, isNot(contains('GET /v1/clinic/staff')));
  });

  testWidgets('mật khẩu tạm: phải đổi trước khi vào hàng chờ', (tester) async {
    final backend = await pumpApp(
      tester,
      backend: FakeBackend(mustChange: true),
    );
    expect(find.text('Đặt mật khẩu mới'), findsOneWidget);
    expect(find.text('Hàng chờ 19/11/2026'), findsNothing);
    expect(backend.calls, isNot(contains('GET /v1/clinic/worklist')));
    go(tester, '/');
    await tester.pumpAndSettle();
    expect(find.text('Đặt mật khẩu mới'), findsOneWidget);

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await tester.enterText(field('Mật khẩu tạm'), 'sai-mat-khau');
    await tester.enterText(field('Mật khẩu mới'), 'ngan');
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu cần ít nhất 10 ký tự.'), findsOneWidget);

    await tester.enterText(field('Mật khẩu mới'), 'mat-khau-moi-cua-toi');
    await tester.enterText(field('Nhập lại mật khẩu mới'), 'khac-hoan-toan');
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(find.text('Hai mật khẩu chưa khớp.'), findsOneWidget);

    await tester.enterText(
      field('Nhập lại mật khẩu mới'),
      'mat-khau-moi-cua-toi',
    );
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu hiện tại không đúng.'), findsOneWidget);

    await tester.enterText(field('Mật khẩu tạm'), 'k7mq-4xr2-9dpt');
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('POST /v1/staff/password'));
    expect(find.text('Hàng chờ 19/11/2026'), findsOneWidget);
  });

  testWidgets('hồ sơ: nhật ký truy cập, tải thêm', (tester) async {
    final backend = await pumpApp(tester);
    await tester.tap(find.text('Phạm Thị Lan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Nhật ký truy cập'));
    await tester.tap(find.text('Nhật ký truy cập'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('GET /v1/patients/p2/access-log'));
    expect(find.text('Mở hồ sơ lượt khám'), findsOneWidget);
    expect(
      find.text('BS. Nguyễn Thu Hà · Lượt khám 19/11/2026'),
      findsOneWidget,
    );
    expect(find.text('Đồng ý chia sẻ dữ liệu'), findsNothing);

    await tester.tap(find.text('Tải thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Đồng ý chia sẻ dữ liệu'), findsOneWidget);
    expect(find.text('Người bệnh'), findsWidgets);
    expect(find.text('Tải thêm'), findsNothing);
  });
}
