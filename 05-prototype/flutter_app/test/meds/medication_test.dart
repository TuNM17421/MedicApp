import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/router/app_router.dart';
import 'package:medic_app/app/router/app_routes.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/storage/local_vault.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/meds/application/meds_providers.dart';
import 'package:medic_app/features/meds/data/med_reminder_scheduler.dart';
import 'package:medic_app/features/meds/domain/med_reminder_planner.dart';
import 'package:medic_app/features/records/application/records_providers.dart';
import 'package:medic_app/features/visit_prep/reminder_scheduler.dart';
import 'package:medic_app/features/visit_prep/visit_prep.dart';
import 'package:medic_app/main.dart';
import 'package:medic_core/medic_core.dart';
import 'package:timezone/timezone.dart';

import '../visit_prep/reminder_planner_test.dart' show FakeScheduler;

class FakeMedScheduler implements MedReminderScheduler {
  final calls = <List<MedReminder>>[];
  final rings = <bool>[];
  bool onTime = true;

  /// What the phone allows when the alarm is turned on.
  AlarmAccess access = (onTime: true, fullScreen: true);

  @override
  Future<bool> replaceAll(
    List<MedReminder> reminders, {
    bool ring = false,
  }) async {
    calls.add(reminders);
    rings.add(ring);
    return true;
  }

  @override
  Future<AlarmAccess> allowAlarm() async {
    if (access.onTime) onTime = true;
    return access;
  }

  @override
  Future<bool> canRingOnTime() async => onTime;

  @override
  Future<void> allowRingOnTime() async => onTime = true;
}

const _metformin = PrescriptionItem(
  name: 'Metformin',
  strength: '500mg',
  form: 'viên',
  quantity: 20,
  doses: [Dose(DoseSlot.morning, 1), Dose(DoseSlot.evening, 1)],
  meal: MealTiming.after,
  days: 10,
);

const _amlodipin = PrescriptionItem(
  name: 'Amlodipin',
  strength: '5mg',
  form: 'viên',
  quantity: 10,
  doses: [Dose(DoseSlot.morning, 1)],
  days: 10,
);

const _allopurinol = PrescriptionItem(
  name: 'Allopurinol',
  strength: '300mg',
  form: 'viên',
  quantity: 10,
  doses: [Dose(DoseSlot.morning, 1)],
  meal: MealTiming.after,
  days: 10,
);

VisitResult _result(
  String visitId,
  String profileId,
  List<PrescriptionItem> items, {
  DateTime? issuedAt,
}) => VisitResult(
  visitId: visitId,
  profileId: profileId,
  issuedAt: issuedAt ?? DateTime(2026, 10, 14, 6),
  facilityName: 'Phòng khám thử',
  facilityPhone: '',
  doctorName: 'BS. Thử',
  patientName: 'Người thử',
  patientAge: 60,
  patientGender: 'Nam',
  diagnosis: 'Thử',
  items: items,
  advice: const [],
);

DoseLogEntry _taken(String courseId, String day, DoseSlot slot) => DoseLogEntry(
  courseId: courseId,
  day: day,
  slot: slot,
  mark: DoseMark.taken,
  at: DateTime(2026, 10, 14, 7, 5),
);

void main() {
  final self = demoProfiles[0];
  final mother = demoProfiles[1];
  final courses = coursesFrom([
    _result('V1', self.id, [_metformin, _amlodipin]),
  ]);
  final metformin = courses[0];

  group('schedule', () {
    test('doses come from the prescription and change state with time', () {
      expect(metformin.id, 'V1#1');
      expect(metformin.lastDay, DateTime(2026, 10, 23));
      final now = DateTime(2026, 10, 14, 8, 30);
      final doses = dosesOn(now, courses, const {}, now);
      expect(doses.map((d) => (d.at.hour, d.state)), [
        (7, DoseState.missed),
        (7, DoseState.missed),
        (19, DoseState.upcoming),
      ]);
      final log = {
        for (final e in [_taken('V1#1', '2026-10-14', DoseSlot.morning)])
          e.key: e,
      };
      expect(
        dosesOn(
          now,
          courses,
          log,
          DateTime(2026, 10, 14, 7, 30),
        ).map((d) => d.state).take(2),
        [DoseState.taken, DoseState.due],
      );
      expect(dosesOn(DateTime(2026, 10, 24), courses, const {}, now), isEmpty);
    });

    test('a prescription written at noon starts with the evening dose', () {
      final late = coursesFrom([
        _result('V2', self.id, [
          _metformin,
        ], issuedAt: DateTime(2026, 10, 14, 12)),
      ]);
      final now = DateTime(2026, 10, 14, 12);
      expect(dosesOn(now, late, const {}, now).map((d) => d.dose.slot), [
        DoseSlot.evening,
      ]);
    });

    test('remaining medicine counts doses taken', () {
      final log = [
        _taken('V1#1', '2026-10-14', DoseSlot.morning),
        _taken('V1#1', '2026-10-14', DoseSlot.evening),
        _taken('V1#2', '2026-10-14', DoseSlot.morning),
      ];
      expect(remainingOf(metformin, log), 18);
      expect(daysLeft(metformin, log), 9);
      expect(daysLeft(courses[1], log), 9);
    });

    test('adherence counts only doses already past due', () {
      final log = {
        for (final e in [_taken('V1#1', '2026-10-14', DoseSlot.morning)])
          e.key: e,
      };
      final day = DateTime(2026, 10, 14);
      expect(adherenceOn(day, courses, log, DateTime(2026, 10, 14, 10)), 0.5);
      expect(
        adherenceOn(day, courses, const {}, DateTime(2026, 10, 14, 6)),
        isNull,
      );
    });
  });

  group('reminders', () {
    test('doses at the same time share one notification and a follow-up', () {
      final plan = planMedReminders(
        courses: courses,
        log: const {},
        profiles: demoProfiles,
        now: DateTime(2026, 10, 14, 6),
      );
      final first = plan.first;
      expect(first.kind, MedReminderKind.dose);
      expect(first.at, DateTime(2026, 10, 14, 7));
      expect(first.title, 'Đến giờ uống thuốc');
      expect(first.summary, '2 thuốc: Metformin, Amlodipin');
      expect(first.doseKeys, hasLength(2));
      expect(first.lines.first.text, '1 viên, sau ăn');
      expect(plan[1].kind, MedReminderKind.followUp);
      expect(plan[1].at, DateTime(2026, 10, 14, 7, 30));
      expect(plan[1].title, 'Bạn đã uống thuốc 07:00 chưa?');
      expect(
        plan.every((r) => !r.at.isAfter(DateTime(2026, 10, 16, 6))),
        isTrue,
      );
    });

    test('recorded doses are not reminded; family doses name the person', () {
      final both = coursesFrom([
        _result('V1', self.id, [_metformin]),
        _result('V3', mother.id, [_allopurinol]),
      ]);
      final log = {
        for (final e in [_taken('V1#1', '2026-10-14', DoseSlot.morning)])
          e.key: e,
      };
      final plan = planMedReminders(
        courses: both,
        log: log,
        profiles: demoProfiles,
        now: DateTime(2026, 10, 14, 6),
      );
      final morning = plan.where((r) => r.at == DateTime(2026, 10, 14, 7));
      expect(morning.single.title, 'Mẹ Lan: đến giờ uống thuốc');
      expect(morning.single.header, 'Mẹ Lan · 07:00');
    });

    test('warns at 08:30 on the day five days of medicine are left', () {
      final plan = planMedReminders(
        courses: courses,
        log: const {},
        profiles: demoProfiles,
        now: DateTime(2026, 10, 18, 6),
      );
      final low = plan.where((r) => r.kind == MedReminderKind.lowStock);
      // 10 days of Metformin from 14/10, none marked taken, so the count
      // still says 10 days: the warning is 5 days from now.
      expect(low, isEmpty);
      final soon = planMedReminders(
        courses: courses,
        log: const {},
        profiles: demoProfiles,
        now: DateTime(2026, 10, 14, 6),
      ).where((r) => r.kind == MedReminderKind.lowStock);
      expect(soon, isEmpty);
      final taken = {
        for (var d = 14; d < 19; d++)
          for (final slot in [DoseSlot.morning, DoseSlot.evening])
            _taken('V1#1', '2026-10-$d', slot).key: _taken(
              'V1#1',
              '2026-10-$d',
              slot,
            ),
      };
      final warn = planMedReminders(
        courses: [metformin],
        log: taken,
        profiles: demoProfiles,
        now: DateTime(2026, 10, 18, 20),
      ).where((r) => r.kind == MedReminderKind.lowStock);
      expect(warn, isEmpty, reason: 'exactly 5 days left: shown in-app');
      taken.remove(doseKey('V1#1', '2026-10-18', DoseSlot.evening));
      taken.remove(doseKey('V1#1', '2026-10-18', DoseSlot.morning));
      final next = planMedReminders(
        courses: [metformin],
        log: taken,
        profiles: demoProfiles,
        now: DateTime(2026, 10, 18, 20),
      ).where((r) => r.kind == MedReminderKind.lowStock);
      expect(next.single.at, DateTime(2026, 10, 19, 8, 30));
      expect(next.single.title, 'Sắp hết Metformin');
    });
  });

  group('notification buttons', () {
    test('the payload round-trips and "Đã uống" is kept for the app', () async {
      const payload = MedPayload(
        keys: ['V1#1|2026-10-14|morning'],
        title: 'Đến giờ uống thuốc',
        summary: 'Metformin',
        header: 'Thuốc của bạn · 07:00',
        html: '<b>Metformin 500mg:</b> 1 viên',
        followUpId: 1001,
      );
      final decoded = MedPayload.decode(payload.encode())!;
      expect(decoded.keys, payload.keys);
      expect(decoded.followUpId, 1001);
      expect(MedPayload.decode('visit:V1'), isNull);
      expect(LocalReminderScheduler.visitIdOf('visit:V1'), 'V1');
      expect(LocalReminderScheduler.visitIdOf('V1'), 'V1');
      expect(LocalReminderScheduler.visitIdOf(payload.encode()), isNull);

      final store = MemoryPendingDoseStore();
      final plugin = _RecordingPlugin();
      final handled = await handleMedAction(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: MedActions.taken,
          payload: payload.encode(),
        ),
        plugin: plugin,
        store: store,
        now: DateTime(2026, 10, 14, 7, 2),
      );
      expect(handled, isTrue);
      expect(plugin.cancelled, [1001]);
      final pending = await store.drain();
      expect(pending.single.key, 'V1#1|2026-10-14|morning');
    });
  });

  group('alarm', () {
    const dose = MedPayload(
      keys: ['V1#1|2026-10-14|morning'],
      title: 'Đến giờ uống thuốc',
      summary: 'Metformin',
      header: 'Thuốc của bạn · 07:00',
      html: '<b>Metformin 500mg:</b> 1 viên',
      ring: true,
    );

    test('rings on the alarm channel until answered', () {
      expect(MedPayload.decode(dose.encode())!.ring, isTrue);
      final ring = medDetails(dose);
      expect(ring.channelId, 'med_alarms');
      expect(ring.audioAttributesUsage, AudioAttributesUsage.alarm);
      expect(ring.category, AndroidNotificationCategory.alarm);
      expect(ring.fullScreenIntent, isTrue);
      expect(ring.additionalFlags, [4]);
      expect(ring.actions, hasLength(2));

      final plain = medDetails(
        MedPayload.decode(dose.encode().replaceFirst('"r":true', '"r":false'))!,
      );
      expect(plain.channelId, 'med_reminders');
      expect(plain.audioAttributesUsage, AudioAttributesUsage.notification);
      expect(plain.fullScreenIntent, isFalse);
      expect(plain.additionalFlags, isNull);
    });

    test('a snoozed alarm rings again, or notifies when exact alarms were '
        'taken back', () async {
      Future<_RecordingPlugin> snooze({required bool exact}) async {
        final plugin = _RecordingPlugin()..exact = exact;
        await handleMedAction(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            actionId: MedActions.snooze,
            payload: dose.encode(),
          ),
          plugin: plugin,
          store: MemoryPendingDoseStore(),
          now: DateTime(2026, 10, 14, 7, 2),
        );
        return plugin;
      }

      final allowed = await snooze(exact: true);
      expect(allowed.modes, [AndroidScheduleMode.alarmClock]);
      expect(allowed.channels, ['med_alarms']);
      final revoked = await snooze(exact: false);
      expect(revoked.modes, [
        AndroidScheduleMode.alarmClock,
        AndroidScheduleMode.inexactAllowWhileIdle,
      ]);
    });

    test('turns on only when exact alarms are allowed', () async {
      final meds = FakeMedScheduler()
        ..access = (onTime: false, fullScreen: false);
      final setting = MemoryMedAlarmSetting();
      final c = ProviderContainer(
        overrides: [
          medReminderSchedulerProvider.overrideWithValue(meds),
          medAlarmSettingProvider.overrideWithValue(setting),
        ],
      );
      addTearDown(c.dispose);
      final alarm = c.read(medAlarmProvider.notifier);

      expect((await alarm.turnOn()).onTime, isFalse);
      expect(c.read(medAlarmProvider), isFalse);
      expect(setting.on, isFalse);

      meds.access = (onTime: true, fullScreen: false);
      expect((await alarm.turnOn()).fullScreen, isFalse);
      expect(c.read(medAlarmProvider), isTrue);
      expect(setting.on, isTrue);

      await alarm.turnOff();
      expect(c.read(medAlarmProvider), isFalse);
      expect(setting.on, isFalse);
    });
  });

  group('dose log', () {
    ProviderContainer container(PendingDoseStore store) {
      final c = ProviderContainer(
        overrides: [
          localVaultProvider.overrideWithValue(MemoryVault()),
          prepClockProvider.overrideWithValue(
            () => DateTime(2026, 10, 14, 7, 10),
          ),
          pendingDoseStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('belongs to the account, survives JSON and picks up '
        'notification taps', () async {
      final store = MemoryPendingDoseStore();
      final c = container(store);
      final auth = c.read(authSessionProvider.notifier);
      auth.signIn(demoPhone, demoPassword);
      auth.updateAccount(
        (a) => a.copyWith(
          results: [
            _result('V1', self.id, [_metformin, _amlodipin]),
          ],
        ),
      );
      c.invalidate(visitResultsProvider);
      final log = c.read(doseLogProvider.notifier);
      log.taken('V1#1|2026-10-14|morning');
      log.skipped('V1#2|2026-10-14|morning', SkipReason.outOfStock);
      expect(c.read(doseLogProvider), hasLength(2));

      await store.add([
        'V1#1|2026-10-14|evening',
        'V9#1|2026-10-14|noon',
      ], DateTime(2026, 10, 14, 19, 3));
      expect(await log.drainPending(), 1);
      expect(
        c.read(doseLogProvider)['V1#1|2026-10-14|evening']!.at,
        DateTime(2026, 10, 14, 19, 3),
      );
      // A dose of another account's course waits for that account.
      expect((await store.drain()).single.key, 'V9#1|2026-10-14|noon');

      final account = c.read(mockAccountStoreProvider)[demoPhone]!;
      final copy = MockAccount.fromJson(account.toJson());
      expect(copy.doseLog, hasLength(3));
      expect(
        copy.doseLog.firstWhere((e) => e.mark == DoseMark.skipped).reason,
        SkipReason.outOfStock,
      );

      auth.signOut();
      auth.signUp('0987654321', '123456');
      expect(c.read(doseLogProvider), isEmpty);
      auth.signOut();
      auth.signIn(demoPhone, demoPassword);
      expect(c.read(doseLogProvider), hasLength(3));

      log.undo('V1#2|2026-10-14|morning');
      expect(c.read(doseLogProvider), hasLength(2));
    });
  });

  testWidgets('Thuốc hôm nay: mark taken, skip with a reason, undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final meds = FakeMedScheduler()..onTime = false;
    final c = ProviderContainer(
      overrides: [
        bookingTodayProvider.overrideWithValue(DateTime(2026, 10, 14)),
        prepClockProvider.overrideWithValue(
          () => DateTime(2026, 10, 14, 7, 20),
        ),
        localVaultProvider.overrideWithValue(MemoryVault()),
        reminderSchedulerProvider.overrideWithValue(FakeScheduler()),
        medReminderSchedulerProvider.overrideWithValue(meds),
        pendingDoseStoreProvider.overrideWithValue(MemoryPendingDoseStore()),
        medAlarmSettingProvider.overrideWithValue(MemoryMedAlarmSetting()),
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
    auth.updateAccount(
      (a) => a.copyWith(
        results: [
          _result('V1', self.id, [_metformin]),
          _result('V3', mother.id, [_allopurinol]),
        ],
      ),
    );
    c.invalidate(visitResultsProvider);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-meds')), findsOneWidget);
    expect(find.text('Còn 3 liều · tiếp theo 07:00'), findsOneWidget);
    expect(meds.calls.last, isNotEmpty);

    c.read(appRouterProvider).push(AppRoutes.meds);
    await tester.pumpAndSettle();
    expect(find.text('Đã uống 0/3 liều'), findsOneWidget);
    expect(find.text('Thuốc của bạn'), findsOneWidget);
    expect(find.text('Bật nhắc đúng giờ'), findsOneWidget);

    // Turning the alarm on asks for exact alarms, so the warning goes.
    expect(meds.rings.last, isFalse);
    await tester.tap(find.byKey(const Key('meds-alarm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meds-alarm-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Đã bật chuông báo uống thuốc.'), findsOneWidget);
    expect(meds.rings.last, isTrue);
    expect(find.text('Bật nhắc đúng giờ'), findsNothing);

    const mine = 'V1#1|2026-10-14|morning';
    await tester.tap(find.byKey(const Key('dose-take-$mine')));
    await tester.pumpAndSettle();
    expect(find.text('Đã uống lúc 07:20'), findsOneWidget);
    expect(find.text('Đã uống 1/3 liều'), findsOneWidget);
    // The plan drops the reminders for that dose.
    expect(meds.calls.last.any((r) => r.doseKeys.contains(mine)), isFalse);

    const hers = 'V3#1|2026-10-14|morning';
    final skip = find.byKey(const Key('dose-skip-$hers'));
    await tester.scrollUntilVisible(
      skip,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(skip), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(find.text('Mẹ Lan'), findsOneWidget);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skip-reason-unwell')));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ liều: Thấy khó chịu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dose-undo-$hers')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dose-take-$hers')), findsOneWidget);

    final saved = c.read(mockAccountStoreProvider)[demoPhone]!.doseLog;
    expect(saved.single.key, mine);
  });
}

class _RecordingPlugin implements FlutterLocalNotificationsPlugin {
  final cancelled = <int>[];
  final modes = <AndroidScheduleMode>[];
  final channels = <String>[];

  /// Whether exact alarms are allowed; alarm-clock schedules fail without.
  bool exact = true;

  @override
  Future<void> zonedSchedule({
    required int id,
    required TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    modes.add(androidScheduleMode);
    if (!exact && androidScheduleMode == AndroidScheduleMode.alarmClock) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    channels.add(notificationDetails.android!.channelId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelled.add(id);
}
