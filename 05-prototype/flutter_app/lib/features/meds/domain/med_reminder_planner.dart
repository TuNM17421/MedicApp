import 'package:intl/intl.dart';

import '../../../app/state/app_state.dart';
import '../../records/domain/visit_result.dart';
import '../../visit_prep/reminder_planner.dart' show ReminderLine;
import 'medication.dart';

enum MedReminderKind {
  /// At the dose time.
  dose,

  /// 30 minutes later, only while the dose is still not recorded.
  followUp,

  /// When about [lowStockDays] days of a medicine are left.
  lowStock,
}

/// Unanswered dose reminders repeat once after this long.
const followUpAfter = Duration(minutes: 30);

/// How far ahead reminders are put on the phone; the plan is rebuilt each
/// time the app opens or a dose is recorded.
const reminderWindow = Duration(hours: 48);

/// A medication notification, laid out like visit reminders: [header] next
/// to the app name, [title] and [summary] collapsed, [lines] expanded.
class MedReminder {
  const MedReminder({
    required this.kind,
    required this.at,
    required this.profileId,
    required this.doseKeys,
    required this.header,
    required this.title,
    required this.summary,
    required this.lines,
  });
  final MedReminderKind kind;
  final DateTime at;
  final String profileId;

  /// The doses this reminder is about; "Đã uống" records all of them.
  final List<String> doseKeys;
  final String header, title, summary;
  final List<ReminderLine> lines;

  /// Stable within a plan, so a follow-up and its dose reminder can be told
  /// apart and cancelled together.
  String get key => '${kind.name}|${doseKeys.join(',')}';

  String get html => [
    for (final line in lines)
      '<b>${_escape(line.label)}:</b> ${_escape(line.text)}',
  ].join('<br>');

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  bool operator ==(Object other) =>
      other is MedReminder &&
      other.key == key &&
      other.at == at &&
      other.title == title &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(key, at, title, summary);
}

String whoShort(PreviewProfile? profile) => profile == null
    ? ''
    : profile.relationship == selfRelationship
    ? 'Bạn'
    : '${profile.relationship} ${profile.name.split(' ').last}';

String _doseText(PrescriptionItem item, Dose dose) => [
  '${formatAmount(dose.amount)} ${item.form}',
  if (item.meal != MealTiming.any) item.meal.label,
  if (item.note.isNotEmpty) item.note.toLowerCase(),
].join(', ');

/// Dose, follow-up and low-stock reminders due within [reminderWindow] of
/// [now]. Doses for the same person at the same time share one notification.
List<MedReminder> planMedReminders({
  required List<MedicationCourse> courses,
  required Map<String, DoseLogEntry> log,
  required List<PreviewProfile> profiles,
  required DateTime now,
}) {
  final until = now.add(reminderWindow);
  final time = DateFormat('HH:mm');
  final groups = <(String, DateTime), List<ScheduledDose>>{};
  for (
    var day = dayOf(now);
    !day.isAfter(until);
    day = day.add(const Duration(days: 1))
  ) {
    for (final dose in dosesOn(day, courses, log, now)) {
      if (dose.entry != null) continue;
      groups.putIfAbsent((dose.course.profileId, dose.at), () => []).add(dose);
    }
  }
  PreviewProfile? profile(String id) =>
      profiles.where((p) => p.id == id).firstOrNull;

  final plan = <MedReminder>[];
  for (final MapEntry(key: (profileId, at), value: doses) in groups.entries) {
    final who = profile(profileId);
    final self = who?.relationship == selfRelationship;
    final name = whoShort(who);
    final header =
        '${self || who == null ? 'Thuốc của bạn' : name} · ${time.format(at)}';
    final keys = [for (final dose in doses) dose.key];
    final lines = [
      for (final dose in doses)
        ReminderLine(
          dose.course.item.title,
          _doseText(dose.course.item, dose.dose),
        ),
    ];
    final names = doses.map((d) => d.course.item.name).join(', ');
    final count = doses.length == 1 ? names : '${doses.length} thuốc: $names';
    if (at.isAfter(now) && !at.isAfter(until)) {
      plan.add(
        MedReminder(
          kind: MedReminderKind.dose,
          at: at,
          profileId: profileId,
          doseKeys: keys,
          header: header,
          title: self || who == null
              ? 'Đến giờ uống thuốc'
              : '$name: đến giờ uống thuốc',
          summary: count,
          lines: lines,
        ),
      );
    }
    final again = at.add(followUpAfter);
    if (again.isAfter(now) && !again.isAfter(until)) {
      plan.add(
        MedReminder(
          kind: MedReminderKind.followUp,
          at: again,
          profileId: profileId,
          doseKeys: keys,
          header: header,
          title: self || who == null
              ? 'Bạn đã uống thuốc ${time.format(at)} chưa?'
              : '$name đã uống thuốc ${time.format(at)} chưa?',
          summary: 'Bấm "Đã uống" để ghi lại. $count',
          lines: lines,
        ),
      );
    }
  }

  final today = dayOf(now);
  final entries = log.values.toList();
  for (final course in courses) {
    final left = daysLeft(course, entries);
    if (left <= lowStockDays) continue;
    final day = today.add(Duration(days: left - lowStockDays));
    if (day.isAfter(course.lastDay)) continue;
    final at = DateTime(day.year, day.month, day.day, 8, 30);
    if (!at.isAfter(now) || at.isAfter(until)) continue;
    final who = profile(course.profileId);
    final self = who?.relationship == selfRelationship;
    plan.add(
      MedReminder(
        kind: MedReminderKind.lowStock,
        at: at,
        profileId: course.profileId,
        doseKeys: [course.id],
        header: self || who == null ? 'Thuốc của bạn' : whoShort(who),
        title: 'Sắp hết ${course.item.name}',
        summary:
            'Còn khoảng $lowStockDays ngày thuốc. Đặt lịch tái khám để lấy đơn mới.',
        lines: [
          ReminderLine('Thuốc', course.item.title),
          ReminderLine('Còn lại', 'khoảng $lowStockDays ngày'),
        ],
      ),
    );
  }
  plan.sort((a, b) => a.at.compareTo(b.at));
  return List.unmodifiable(plan);
}
