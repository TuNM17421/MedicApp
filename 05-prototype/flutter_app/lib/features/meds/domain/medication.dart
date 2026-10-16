import 'package:flutter/foundation.dart';

import '../../records/domain/visit_result.dart';

DateTime dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

String dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// One medicine from one prescription, taken from the day it was prescribed
/// for the number of days the doctor wrote.
@immutable
class MedicationCourse {
  const MedicationCourse({
    required this.id,
    required this.profileId,
    required this.visitId,
    required this.item,
    required this.prescribedAt,
  });

  /// `<visitId>#<line number>`, stable across app restarts.
  final String id;
  final String profileId, visitId;
  final PrescriptionItem item;
  final DateTime prescribedAt;

  DateTime get firstDay => dayOf(prescribedAt);
  DateTime get lastDay => firstDay.add(Duration(days: item.days - 1));

  bool activeOn(DateTime day) {
    final d = dayOf(day);
    return !d.isBefore(firstDay) && !d.isAfter(lastDay);
  }

  /// Scheduled time of [dose] on [day]. Doses due before the prescription
  /// was written on its first day are not expected.
  DateTime? timeOn(DateTime day, Dose dose) {
    if (!activeOn(day)) return null;
    final at = DateTime(
      day.year,
      day.month,
      day.day,
      dose.slot.hour,
      dose.slot.minute,
    );
    return at.isBefore(prescribedAt) ? null : at;
  }
}

List<MedicationCourse> coursesFrom(Iterable<VisitResult> results) => [
  for (final result in results)
    for (final (index, item) in result.items.indexed)
      MedicationCourse(
        id: '${result.visitId}#${index + 1}',
        profileId: result.profileId,
        visitId: result.visitId,
        item: item,
        prescribedAt: result.issuedAt,
      ),
];

enum DoseMark { taken, skipped }

enum SkipReason {
  forgot('Quên uống'),
  outOfStock('Hết thuốc'),
  unwell('Thấy khó chịu'),
  other('Lý do khác');

  const SkipReason(this.label);
  final String label;
}

/// What the person recorded for one dose.
@immutable
class DoseLogEntry {
  const DoseLogEntry({
    required this.courseId,
    required this.day,
    required this.slot,
    required this.mark,
    required this.at,
    this.reason,
  });
  final String courseId;

  /// `yyyy-MM-dd` of the scheduled day.
  final String day;
  final DoseSlot slot;
  final DoseMark mark;

  /// When it was recorded.
  final DateTime at;
  final SkipReason? reason;

  String get key => doseKey(courseId, day, slot);

  Map<String, Object?> toJson() => {
    'courseId': courseId,
    'day': day,
    'slot': slot.name,
    'mark': mark.name,
    'at': at.toIso8601String(),
    'reason': reason?.name,
  };

  factory DoseLogEntry.fromJson(Map<String, Object?> json) => DoseLogEntry(
    courseId: json['courseId']! as String,
    day: json['day']! as String,
    slot: DoseSlot.values.byName(json['slot']! as String),
    mark: DoseMark.values.byName(json['mark']! as String),
    at: DateTime.parse(json['at']! as String),
    reason: switch (json['reason']) {
      final String value => SkipReason.values.byName(value),
      _ => null,
    },
  );
}

String doseKey(String courseId, String day, DoseSlot slot) =>
    '$courseId|$day|${slot.name}';

/// A dose not recorded this long after its time counts as missed.
const missedAfter = Duration(minutes: 60);

enum DoseState { upcoming, due, taken, skipped, missed }

/// A dose on the Today list.
@immutable
class ScheduledDose {
  const ScheduledDose({
    required this.course,
    required this.dose,
    required this.at,
    required this.state,
    this.entry,
  });
  final MedicationCourse course;
  final Dose dose;
  final DateTime at;
  final DoseState state;
  final DoseLogEntry? entry;

  String get key => doseKey(course.id, dayKey(at), dose.slot);
}

DoseState stateOf(DateTime at, DoseLogEntry? entry, DateTime now) {
  if (entry != null) {
    return entry.mark == DoseMark.taken ? DoseState.taken : DoseState.skipped;
  }
  if (now.isBefore(at)) return DoseState.upcoming;
  if (now.difference(at) < missedAfter) return DoseState.due;
  return DoseState.missed;
}

/// Every dose due on [day], in time order.
List<ScheduledDose> dosesOn(
  DateTime day,
  List<MedicationCourse> courses,
  Map<String, DoseLogEntry> log,
  DateTime now,
) {
  final doses = <ScheduledDose>[
    for (final course in courses)
      for (final dose in course.item.doses)
        if (course.timeOn(day, dose) case final at?)
          ScheduledDose(
            course: course,
            dose: dose,
            at: at,
            entry: log[doseKey(course.id, dayKey(day), dose.slot)],
            state: stateOf(
              at,
              log[doseKey(course.id, dayKey(day), dose.slot)],
              now,
            ),
          ),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return doses;
}

/// Units left, assuming every dose marked taken used its amount.
num remainingOf(MedicationCourse course, Iterable<DoseLogEntry> log) {
  final perSlot = {for (final d in course.item.doses) d.slot: d.amount};
  final used = log
      .where((e) => e.courseId == course.id && e.mark == DoseMark.taken)
      .fold<num>(0, (sum, e) => sum + (perSlot[e.slot] ?? 0));
  final left = course.item.quantity - used;
  return left < 0 ? 0 : left;
}

/// Days of medicine left at the prescribed daily amount.
int daysLeft(MedicationCourse course, Iterable<DoseLogEntry> log) {
  final daily = course.item.dailyAmount;
  if (daily <= 0) return 0;
  return (remainingOf(course, log) / daily).floor();
}

/// Warn when this many days or fewer remain, so there is time to book a
/// follow-up visit for a new prescription.
const lowStockDays = 5;

/// Share of doses taken among doses already due on [day] (null when none).
double? adherenceOn(
  DateTime day,
  List<MedicationCourse> courses,
  Map<String, DoseLogEntry> log,
  DateTime now,
) {
  final due = dosesOn(
    day,
    courses,
    log,
    now,
  ).where((d) => d.state != DoseState.upcoming && d.state != DoseState.due);
  if (due.isEmpty) return null;
  final taken = due.where((d) => d.state == DoseState.taken).length;
  return taken / due.length;
}
