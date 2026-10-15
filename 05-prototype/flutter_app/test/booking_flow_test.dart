import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medic_app/core/widgets/app_widgets.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';

import 'app_navigation_test.dart' show openApp, tapText;

Future<void> press(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('booking-action')),
      matching: find.byType(AppPrimaryButton),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> chooseToReview(
  WidgetTester tester, {
  bool insurance = false,
}) async {
  await press(tester, insurance ? 'type-insurance' : 'type-service');
  await next(tester);
  await press(
    tester,
    insurance ? 'booking-patient-mother' : 'booking-patient-self',
  );
  await next(tester);
  await press(tester, 'facility-anbinh');
  await next(tester);
  await press(tester, 'department-general');
  await next(tester);
  await press(tester, 'doctor-any');
  await next(tester);
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('booking-action'))),
  );
  final slots = container
      .read(bookingSessionProvider)
      .slots
      .where((slot) => slot.available)
      .toList();
  expect(slots, isNotEmpty);
  await press(tester, 'booking-slot-${slots.first.time}');
  await next(tester);
}

void main() {
  setUpAll(() async {
    final font = FontLoader('BeVietnamPro');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      font.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
  });

  testWidgets('service journey, receipt, history and preserved footer', (
    tester,
  ) async {
    final c = await openApp(
      tester,
      location: '/booking',
      size: const Size(412, 915),
    );
    await next(tester);
    expect(find.textContaining('Vui lòng chọn'), findsOneWidget);
    await chooseToReview(tester);
    expect(c.read(bookingSessionProvider).stage, BookingStage.review);
    await expectLater(
      find.byKey(const Key('shell-capture')),
      matchesGoldenFile('goldens/booking-review-412.png'),
    );
    await next(tester);
    await press(tester, 'payment-wallet');
    await expectLater(
      find.byKey(const Key('shell-capture')),
      matchesGoldenFile('goldens/booking-payment-412.png'),
    );
    await next(tester);
    expect(find.text('Đặt lịch thành công'), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-nav')), findsNothing);
    await expectLater(
      find.byKey(const Key('shell-capture')),
      matchesGoldenFile('goldens/booking-result-412.png'),
    );
    await next(tester);
    expect(find.byKey(const Key('app-bottom-nav')), findsOneWidget);
    expect(find.text('Đã xác nhận'), findsOneWidget);
    await tapText(tester, 'Phạm Văn Hòa');
    expect(find.text('Chi tiết lịch hẹn'), findsOneWidget);
    expect(find.textContaining('Mã lịch: LK-'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BHYT journey at large text completes without overflow', (
    tester,
  ) async {
    final c = await openApp(tester, location: '/booking', scale: 2);
    await chooseToReview(tester, insurance: true);
    await next(tester);
    expect(c.read(bookingSessionProvider).stage, BookingStage.payment);
    expect(find.byKey(const Key('payment-card')), findsNothing);
    await press(tester, 'payment-atHospital');
    await next(tester);
    expect(
      c.read(appointmentsProvider).records.single.receipt.status,
      PaymentStatus.confirmed,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('new patient validates date and becomes selected', (
    tester,
  ) async {
    final c = await openApp(tester, location: '/booking');
    await press(tester, 'type-service');
    await next(tester);
    await tapText(tester, 'Thêm người khám');
    await tapText(tester, 'Lưu người khám');
    expect(find.text('Vui lòng nhập họ và tên.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('new-patient-name')),
      'Nguyễn An',
    );
    await tester.enterText(
      find.byKey(const Key('new-patient-dob')),
      '31/02/2018',
    );
    await tapText(tester, 'Lưu người khám');
    expect(find.text('Nhập ngày sinh hợp lệ theo dd/MM/yyyy.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('new-patient-dob')),
      '12/02/2018',
    );
    await tapText(tester, 'Lưu người khám');
    expect(c.read(bookingSessionProvider).draft.patientId, startsWith('P'));
    await next(tester);
    expect(c.read(bookingSessionProvider).stage, BookingStage.facility);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unresolved payment exposes status checks and never retry payment',
    (tester) async {
      final c = await openApp(tester, location: '/booking');
      c
          .read(demoOptionsProvider.notifier)
          .set(const DemoOptions(outcome: DemoOutcome.unknown));
      await chooseToReview(tester);
      await next(tester);
      await press(tester, 'payment-card');
      await next(tester);
      expect(
        c.read(appointmentsProvider).records.single.receipt.appointmentCode,
        isNull,
      );
      expect(find.text('Thử lại hoặc đổi cách thanh toán'), findsNothing);
      // The action remains accessible after scrolling the ticket.
      await tester.scrollUntilVisible(
        find.text('Kiểm tra trạng thái'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tapText(tester, 'Kiểm tra trạng thái');
      await tapText(tester, 'Kiểm tra trạng thái');
      expect(
        c.read(appointmentsProvider).records.single.receipt.status,
        PaymentStatus.confirmed,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
