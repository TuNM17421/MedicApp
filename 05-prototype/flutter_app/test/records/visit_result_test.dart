import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/router/app_router.dart';
import 'package:medic_app/app/router/app_routes.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/storage/local_vault.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/consent/health_consent.dart';
import 'package:medic_app/features/records/application/records_providers.dart';
import 'package:medic_app/features/records/data/doctor_portal.dart';
import 'package:medic_core/medic_core.dart';
import 'package:medic_app/features/visit_prep/reminder_scheduler.dart';
import 'package:medic_app/features/visit_prep/visit_prep.dart';
import 'package:medic_app/main.dart';

import '../visit_prep/reminder_planner_test.dart' show FakeScheduler;
import '../visit_prep/visit_prep_test.dart' show visit, receipt;

final _motherVisit = visit(
  id: 'V7',
  patientId: 'mother',
  departmentId: 'bones',
  departmentName: 'Cơ Xương Khớp',
  date: DateTime(2026, 10, 20),
  time: '14:30',
);

void main() {
  final mother = demoProfiles[1];
  final child = demoProfiles[2];

  group('prescription lines', () {
    const metformin = PrescriptionItem(
      name: 'Metformin',
      strength: '500mg',
      form: 'viên',
      quantity: 60,
      doses: [Dose(DoseSlot.morning, 1), Dose(DoseSlot.evening, 1)],
      meal: MealTiming.after,
      days: 30,
    );

    test('read like the paper form and like the app', () {
      expect(metformin.title, 'Metformin 500mg');
      expect(metformin.schedule, 'Sáng 1 viên, tối 1 viên, sau ăn');
      expect(
        metformin.usageLine,
        'Ngày uống 2 lần, mỗi lần 1 viên, sáng - tối, sau ăn',
      );
      expect(metformin.dailyAmount, 2);

      const split = PrescriptionItem(
        name: 'Bisoprolol',
        strength: '2,5mg',
        form: 'viên',
        quantity: 15,
        doses: [Dose(DoseSlot.morning, 1), Dose(DoseSlot.evening, 0.5)],
        days: 10,
      );
      expect(split.schedule, 'Sáng 1 viên, tối 1/2 viên');
      expect(split.usageLine, 'Ngày uống 2 lần, sáng 1 viên, tối 1/2 viên');
    });
  });

  group('mock doctor portal', () {
    test('prescribes for the conditions the patient is followed for', () {
      final result = MockDoctorPortal.buildResult(_motherVisit, mother);
      expect(result.profileId, 'mother');
      expect(result.items.map((item) => item.title), [
        'Allopurinol 300mg',
        'Atorvastatin 10mg',
      ]);
      expect(result.diagnosis, 'Gút (M10); Rối loạn lipid máu (E78)');
      expect(result.issuedAt, DateTime(2026, 10, 20, 14, 30));
      expect(result.followUpDate, DateTime(2026, 11, 19));
      expect(result.advice.last, 'Hẹn tái khám ngày 19/11/2026.');
      expect(result.patientAge, 78);
    });

    test('prescribes nothing when no condition is followed', () {
      final result = MockDoctorPortal.buildResult(
        visit(patientId: 'child'),
        child,
      );
      expect(result.items, isEmpty);
      expect(result.followUpDate, DateTime(2027, 4, 14));
    });

    test('result and appointment survive the vault round trip', () {
      final account = MockAccount(
        phone: demoPhone,
        password: demoPassword,
        appointments: [AppointmentRecord(_motherVisit, receipt)],
        results: [MockDoctorPortal.buildResult(_motherVisit, mother)],
      );
      final json =
          jsonDecode(jsonEncode(account.toJson())) as Map<String, Object?>;
      final back = MockAccount.fromJson(json);
      expect(back.appointments.single.visit.time, '14:30');
      expect(back.appointments.single.receipt.appointmentCode, 'MA123');
      final result = back.results.single;
      expect(result.items.first.schedule, 'Sáng 1 viên, sau ăn');
      expect(result.items.first.note, 'Uống nhiều nước trong ngày');
      expect(result.followUpDate, DateTime(2026, 11, 19));
    });
  });

  test('appointments and results belong to the signed-in account', () async {
    final c = ProviderContainer(
      overrides: [
        doctorPortalProvider.overrideWithValue(
          const MockDoctorPortal(latency: Duration.zero),
        ),
      ],
    );
    addTearDown(c.dispose);
    final auth = c.read(authSessionProvider.notifier);
    auth.signIn(demoPhone, demoPassword);
    c
        .read(appointmentsProvider.notifier)
        .upsert(AppointmentRecord(_motherVisit, receipt));
    await c.read(visitResultsProvider.notifier).fetch('V7');
    expect(c.read(visitResultsProvider).forVisit('V7'), isNotNull);

    auth.signOut();
    auth.signUp('0987654321', '123456');
    expect(c.read(appointmentsProvider).records, isEmpty);
    expect(c.read(visitResultsProvider).results, isEmpty);

    auth.signOut();
    auth.signIn(demoPhone, demoPassword);
    expect(c.read(appointmentsProvider).records.single.visit.id, 'V7');
    expect(c.read(visitResultsProvider).forVisit('V7')!.items, hasLength(2));
  });

  testWidgets('doctor sends the result; both views show the prescription', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vault = MemoryVault();
    final c = ProviderContainer(
      overrides: [
        bookingTodayProvider.overrideWithValue(DateTime(2026, 10, 14)),
        prepClockProvider.overrideWithValue(() => DateTime(2026, 10, 14, 10)),
        doctorPortalProvider.overrideWithValue(
          const MockDoctorPortal(latency: Duration.zero),
        ),
        localVaultProvider.overrideWithValue(vault),
        reminderSchedulerProvider.overrideWithValue(FakeScheduler()),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MedicApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    final auth = c.read(authSessionProvider.notifier);
    auth.signIn(demoPhone, demoPassword);
    auth.setConsent(
      HealthConsent(version: healthConsentVersion, acceptedAt: DateTime(2026)),
    );
    c
        .read(appointmentsProvider.notifier)
        .upsert(AppointmentRecord(_motherVisit, receipt));
    c.read(appRouterProvider).push(AppRoutes.appointment('V7'));
    await tester.pumpAndSettle();

    final simulate = find.byKey(const Key('visit-result-simulate'));
    await tester.scrollUntilVisible(
      simulate,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(simulate), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(simulate);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(c.read(visitResultsProvider).forVisit('V7'), isNotNull);
    await tester.pumpAndSettle();
    expect(find.text('Đã nhận kết quả khám.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('visit-result-open')));
    await tester.pumpAndSettle();
    expect(find.text('Allopurinol 300mg'), findsOneWidget);
    expect(find.text('Sáng 1 viên, sau ăn'), findsOneWidget);

    await tester.tap(find.text('Bản đơn thuốc'));
    await tester.pumpAndSettle();
    expect(find.text('ĐƠN THUỐC'), findsOneWidget);
    expect(find.text('1. Allopurinol 300mg'), findsOneWidget);

    final saved = VaultSnapshot.accounts(await vault.read()).single;
    expect(saved.appointments.single.visit.id, 'V7');
    expect(saved.results.single.items, hasLength(2));
  });
}
