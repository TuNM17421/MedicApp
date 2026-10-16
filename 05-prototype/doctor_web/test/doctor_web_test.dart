import 'package:doctor_web/data/providers.dart';
import 'package:doctor_web/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<FakeBackend> pumpApp(
  WidgetTester tester, {
  bool signedIn = true,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final backend = FakeBackend(signedIn: signedIn);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWithValue(backend.api)],
      child: const DoctorWebApp(),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  testWidgets('chưa đăng nhập thì vào màn đăng nhập; sai mật khẩu báo lỗi', (
    tester,
  ) async {
    await pumpApp(tester, signedIn: false);
    expect(find.text('Đăng nhập'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'bs.ha@anbinh.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'sai');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'medicapp-demo');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Hàng chờ 19/11/2026'), findsOneWidget);
  });

  testWidgets('hàng chờ: tuân thủ tính bằng medic_core, lọc và tìm', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Phạm Thị Lan'), findsOneWidget);
    // Allopurinol 27/30 và Atorvastatin 18/30: 45/60 liều = 75%.
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('Người bệnh không chia sẻ tóm tắt'), findsOneWidget);

    await tester.tap(find.text('Chưa đến  1'));
    await tester.pumpAndSettle();
    expect(find.text('Phạm Thị Lan'), findsNothing);
    expect(find.text('Phạm Văn Hòa'), findsOneWidget);

    await tester.tap(find.text('Tất cả  3'));
    await tester.enterText(find.byType(TextField), '000317');
    await tester.pumpAndSettle();
    expect(find.text('Trần Văn Minh'), findsOneWidget);
    expect(find.text('Phạm Văn Hòa'), findsNothing);
  });

  testWidgets('hồ sơ bà Lan: tóm tắt, câu gốc, tuân thủ từng thuốc', (
    tester,
  ) async {
    final backend = await pumpApp(tester);
    await tester.tap(find.text('Phạm Thị Lan'));
    await tester.pumpAndSettle();

    expect(
      find.text('Đau khớp gối phải khoảng 1 tuần, sưng về đêm.'),
      findsOneWidget,
    );
    expect(find.text('Bắt đầu khám'), findsOneWidget);

    await tester.tap(find.text('Xem câu gốc').first);
    await tester.pumpAndSettle();
    expect(
      find.text('“Dạo này cái gối bên phải đau quá, tối nằm thấy sưng lên.”'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('18/30 liều'));
    await tester.pumpAndSettle();
    expect(find.text('18/30 liều'), findsOneWidget);
    expect(find.text('27/30 liều'), findsOneWidget);
    expect(
      find.textContaining(
        'Cả 5 lần chọn “Thấy khó chịu” đều trong 14 ngày gần nhất',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Bảng'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);

    await tester.ensureVisible(find.text('Đúng, có ích'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đúng, có ích'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('POST /v1/summaries/s-p2/feedback'));
  });

  testWidgets('người bệnh không chia sẻ thì không có tóm tắt', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Phạm Văn Hòa'));
    await tester.pumpAndSettle();
    expect(find.text('Người bệnh không chia sẻ tóm tắt'), findsOneWidget);
    expect(find.text('Đánh dấu đã đến'), findsOneWidget);
    expect(find.text('Tuân thủ thuốc'), findsNothing);
  });

  testWidgets('lịch sử khám hiện đơn thuốc lần trước', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Phạm Thị Lan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lịch sử khám'));
    await tester.pumpAndSettle();
    expect(find.text('20/10/2026'), findsOneWidget);
    expect(
      find.textContaining('Ngày uống 1 lần, mỗi lần 1 viên, sáng, sau ăn'),
      findsOneWidget,
    );
  });

  testWidgets('màn hẹp: thẻ thay bảng, cột người bệnh xếp trên', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 844));
    expect(find.text('GIỜ'), findsNothing);
    expect(find.textContaining('Phạm Thị Lan'), findsOneWidget);
    await tester.tap(find.textContaining('Phạm Thị Lan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Tóm tắt trước khám'),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Tóm tắt trước khám'), findsOneWidget);
  });

  testWidgets('hết phiên thì quay về đăng nhập', (tester) async {
    final backend = await pumpApp(tester);
    backend.signedIn = false;
    await tester.tap(find.text('Phạm Thị Lan'));
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập'), findsOneWidget);
  });

  testWidgets('người bệnh rút lại đồng ý: hồ sơ nói rõ, không có dữ liệu', (
    tester,
  ) async {
    final backend = await pumpApp(tester);
    backend.hoaConsent = {
      'state': 'declined',
      'reason': 'revoked',
      'revokedAt': '2026-11-19T08:10:00+07:00',
    };
    await tester.tap(find.text('Phạm Văn Hòa'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('đã rút lại đồng ý chia sẻ lúc 08:10'),
      findsOneWidget,
    );
    expect(find.text('Tuân thủ thuốc'), findsNothing);
  });
}
