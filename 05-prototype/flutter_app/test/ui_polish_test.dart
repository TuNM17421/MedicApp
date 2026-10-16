import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/widgets/app_widgets.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/booking/presentation/appointment_pages.dart';

import 'app_navigation_test.dart' show openApp;
import 'visit_prep/visit_prep_test.dart' show visit, receipt;

class _OnlySelf extends ProfileCatalogController {
  @override
  List<PreviewProfile> build() => [demoProfiles.first];
}

Finder _animated(String key) => find.ancestor(
  of: find.byKey(Key(key)),
  matching: find.byType(Animate),
);

void main() {
  testWidgets('home cards fade in, but stay still with reduced motion', (
    tester,
  ) async {
    await openApp(tester, disableAnimations: false);
    expect(_animated('home-booking-card'), findsOneWidget);
    await tester.pumpAndSettle();

    await openApp(tester);
    expect(_animated('home-booking-card'), findsNothing);
  });

  testWidgets('empty appointments show an illustration and no calendar', (
    tester,
  ) async {
    await openApp(tester, location: '/home/appointments');
    expect(find.text('Chưa có lịch hẹn'), findsOneWidget);
    expect(find.byType(AppIllustration), findsOneWidget);
    expect(find.byKey(const Key('appointments-calendar')), findsNothing);
  });

  testWidgets('calendar filters the list to the tapped day', (tester) async {
    final c = await openApp(
      tester,
      location: '/home/appointments',
      size: const Size(412, 915),
    );
    final appointments = c.read(appointmentsProvider.notifier);
    appointments.upsert(AppointmentRecord(visit(), receipt));
    appointments.upsert(
      AppointmentRecord(
        visit(id: 'V2', date: DateTime(2026, 10, 20), time: '09:00'),
        receipt,
      ),
    );
    await tester.pumpAndSettle();
    final calendar = find.byKey(const Key('appointments-calendar'));
    expect(find.text('Tháng 10, 2026'), findsOneWidget);
    expect(find.textContaining('08:00'), findsOneWidget);

    await tester.tap(find.descendant(of: calendar, matching: find.text('20')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lịch hẹn ngày'), findsOneWidget);
    expect(find.textContaining('09:00'), findsOneWidget);
    expect(find.textContaining('08:00'), findsNothing);

    await tester.tap(find.byKey(const Key('appointments-show-all')));
    await tester.pumpAndSettle();
    expect(find.textContaining('08:00'), findsOneWidget);
  });

  testWidgets('success mark only for a confirmed booking', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final appointments = c.read(appointmentsProvider.notifier);
    appointments.upsert(AppointmentRecord(visit(), receipt));
    appointments.upsert(
      AppointmentRecord(
        visit(id: 'V2'),
        const PaymentReceipt(
          status: PaymentStatus.failed,
          method: PayMethod.atHospital,
        ),
      ),
    );
    Future<void> show(String id) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(body: BookingSuccessMark(id: id)),
        ),
      ),
    );
    await show('V1');
    await tester.pumpAndSettle();
    expect(find.text('Đã đặt lịch xong'), findsOneWidget);
    await show('V2');
    expect(find.text('Đã đặt lịch xong'), findsNothing);
  });

  testWidgets('profiles invite adding family only when alone', (tester) async {
    await openApp(tester, location: '/profiles');
    expect(find.byKey(const Key('profiles-family-hint')), findsNothing);
    await openApp(
      tester,
      location: '/profiles',
      overrides: [profileCatalogProvider.overrideWith(_OnlySelf.new)],
    );
    expect(find.byKey(const Key('profiles-family-hint')), findsOneWidget);
  });
}
