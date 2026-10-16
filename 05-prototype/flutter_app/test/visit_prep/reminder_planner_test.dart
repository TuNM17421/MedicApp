import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/router/app_router.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/visit_prep/reminder_planner.dart';
import 'package:medic_app/features/visit_prep/reminder_scheduler.dart';
import 'package:medic_app/features/visit_prep/visit_prep.dart';

import '../app_navigation_test.dart' show openApp;
import 'visit_prep_test.dart' show visit, receipt;

List<PlannedReminder> plan(VisitSummary v, PreviewProfile p, DateTime now) =>
    planReminders(
      visit: v,
      patient: p,
      notes: adviseVisit(visit: v, patient: p, now: now),
      now: now,
    );

Map<ReminderKind, DateTime> times(List<PlannedReminder> reminders) => {
  for (final r in reminders) r.kind: r.at,
};

class FakeScheduler implements ReminderScheduler {
  final calls = <List<PlannedReminder>>[];
  bool allowed = true;

  @override
  Future<bool> replaceAll(List<PlannedReminder> reminders) async {
    calls.add(reminders);
    return allowed;
  }
}

void main() {
  final self = demoProfiles[0];
  final mother = demoProfiles[1];
  final child = demoProfiles[2];
  final twoDaysBefore = DateTime(2026, 10, 14, 10);

  test(
    'morning fasting visit: reminded the afternoon before, then at 06:00',
    () {
      final r = plan(visit(), self, twoDaysBefore);
      expect(times(r), {
        ReminderKind.prepare: DateTime(2026, 10, 15, 17),
        ReminderKind.leave: DateTime(2026, 10, 16, 6),
      });
      final prepare = r.first;
      expect(prepare.header, 'Lịch của bạn · Nội tiết');
      expect(prepare.title, 'Nhịn ăn từ nửa đêm nay');
      expect(prepare.summary, 'Khám lúc 08:00 sáng mai');
      expect(
        prepare.lines.first,
        const ReminderLine('Nửa đêm nay', 'Ngừng ăn, chỉ uống nước lọc'),
      );
      expect(r.last.title, 'Khám lúc 08:00 sáng nay');
    },
  );

  test('booked after the afternoon slot: reminded right away', () {
    final now = DateTime(2026, 10, 15, 19, 30);
    final r = plan(visit(), self, now);
    expect(r.first.kind, ReminderKind.prepare);
    expect(r.first.at, now.add(const Duration(minutes: 1)));
  });

  test('24-hour alcohol rule starts two days ahead; short fasting the same morning', () {
    final r = plan(
      visit(
        patientId: 'mother',
        departmentId: 'bones',
        departmentName: 'Cơ Xương Khớp',
        date: DateTime(2026, 10, 17),
        time: '14:30',
      ),
      mother,
      twoDaysBefore,
    );
    expect(times(r), {
      ReminderKind.advance: DateTime(2026, 10, 15, 9),
      ReminderKind.prepare: DateTime(2026, 10, 17, 7),
      ReminderKind.leave: DateTime(2026, 10, 17, 12, 30),
    });
    expect(r.first.header, 'Mẹ Lan · Cơ Xương Khớp');
    expect(r.first.title, 'Từ chiều mai: kiêng rượu bia');
    expect(r.first.body, contains('14:30 chiều mai: Không uống rượu bia'));
    expect(r.first.body, contains('Mẹ Phạm Thị Lan (78 tuổi) khám tại'));
    expect(r[1].lines.first.label, 'Đang kiêng');
    expect(r.last.body, contains('Nên có người nhà đi cùng.'));
  });

  test(
    'afternoon visit whose fasting starts before dawn: reminded the day before',
    () {
      final r = plan(
        visit(
          departmentId: 'heart',
          departmentName: 'Tim mạch',
          date: DateTime(2026, 10, 17),
          time: '14:00',
        ),
        self.withConditions(['dyslipidemia']),
        twoDaysBefore,
      );
      expect(times(r)[ReminderKind.advance], DateTime(2026, 10, 15, 9));
      expect(times(r)[ReminderKind.prepare], DateTime(2026, 10, 16, 17));
    },
  );

  test('visits without preparation still get a plain reminder', () {
    final afternoon = plan(
      visit(departmentId: 'eyes', departmentName: 'Mắt', time: '15:00'),
      self,
      twoDaysBefore,
    );
    expect(afternoon.first.title, 'Lịch khám 15:00 chiều nay');
    expect(times(afternoon), {
      ReminderKind.prepare: DateTime(2026, 10, 16, 7),
      ReminderKind.leave: DateTime(2026, 10, 16, 13),
    });
    final morning = plan(
      visit(departmentId: 'eyes', departmentName: 'Mắt', time: '09:00'),
      self,
      twoDaysBefore,
    );
    expect(times(morning)[ReminderKind.prepare], DateTime(2026, 10, 15, 17));
  });

  test('children: addressed to the adult, with a note on fasting', () {
    final kid = child.withConditions(['diabetes']);
    final v = visit(patientId: 'child');
    final notes = adviseVisit(visit: v, patient: kid, now: twoDaysBefore);
    expect(notes.single.headline, startsWith('Cháu Phạm Minh An (9 tuổi)'));
    expect(
      notes.single.items.map((i) => i.text),
      contains(startsWith('Trẻ nhỏ khó nhịn lâu')),
    );
    final r = plan(v, kid, twoDaysBefore);
    expect(r.last.body, contains('Người lớn đưa bé đi'));
  });

  test(
    'women of child-bearing age are asked about pregnancy before endoscopy',
    () {
      const woman = PreviewProfile(
        id: 'w',
        name: 'Lê Thu Trang',
        birthYear: 1986,
        relationship: 'Vợ',
        gender: 'Nữ',
        conditions: ['gastritis'],
      );
      final notes = adviseVisit(
        visit: visit(
          patientId: 'w',
          departmentId: 'general',
          departmentName: 'Nội tổng quát',
        ),
        patient: woman,
        now: twoDaysBefore,
      );
      expect(
        notes.single.items.map((i) => i.text),
        contains(startsWith('Nếu đang mang thai')),
      );
      expect(
        adviseVisit(
          visit: visit(
            departmentId: 'general',
            departmentName: 'Nội tổng quát',
          ),
          patient: self.withConditions(['gastritis']),
          now: twoDaysBefore,
        ).single.items.map((i) => i.text),
        isNot(contains(startsWith('Nếu đang mang thai'))),
      );
    },
  );

  test('expanded text bolds each label and escapes names', () {
    final r = plan(
      visit(facilityName: 'Phòng khám A & B'),
      self,
      twoDaysBefore,
    ).first;
    expect(r.html, startsWith('<b>Nửa đêm nay:</b> Ngừng ăn'));
    expect(r.html, contains('Phòng khám A &amp; B'));
    expect(r.html.split('<br>'), hasLength(r.lines.length));
  });

  testWidgets(
    'booking an appointment schedules phone reminders and lists them',
    (tester) async {
      final scheduler = FakeScheduler()..allowed = false;
      final c = await openApp(
        tester,
        size: const Size(412, 915),
        overrides: [
          prepClockProvider.overrideWithValue(() => twoDaysBefore),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      c.read(reminderSyncProvider);
      c.read(authSessionProvider.notifier).signIn(demoPhone, demoPassword);
      c
          .read(appointmentsProvider.notifier)
          .upsert(AppointmentRecord(visit(), receipt));
      await tester.pumpAndSettle();
      expect(scheduler.calls.last.map((r) => r.kind), [
        ReminderKind.prepare,
        ReminderKind.leave,
      ]);

      c.read(appRouterProvider).push('/home/appointments/V1');
      await tester.pumpAndSettle();
      final section = find.byKey(const Key('visit-reminders'));
      await tester.ensureVisible(section);
      expect(find.text('17:00 chiều mai'), findsOneWidget);
      expect(find.textContaining('chặn thông báo'), findsOneWidget);

      c.read(authSessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(scheduler.calls.last, isEmpty);
    },
  );
}
