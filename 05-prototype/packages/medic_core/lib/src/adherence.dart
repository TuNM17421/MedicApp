import 'package:meta/meta.dart';

import 'medication.dart';

/// Share of due doses taken at or above which a course counts as followed.
/// 80% is the threshold commonly used with the proportion of days covered
/// (PDC) measure.
const adherenceThreshold = 80;

enum AdherenceLevel {
  good('Đạt'),
  fair('Dưới 80%'),
  low('Thấp');

  const AdherenceLevel(this.label);
  final String label;

  static AdherenceLevel of(int percent) => percent >= adherenceThreshold
      ? good
      : percent >= 60
      ? fair
      : low;
}

/// How one day of a course went, for the 30-day strip on the doctor's screen.
enum DayStatus { taken, partial, missed, none }

/// A due dose with no record. Shown next to the reasons the person chose.
const unrecordedLabel = 'Không ghi nhận';

@immutable
class DayAdherence {
  const DayAdherence({
    required this.day,
    required this.due,
    required this.taken,
    required this.missedReasons,
  });

  /// `yyyy-MM-dd`.
  final String day;

  /// Doses that were due and are past their time, and how many were taken.
  final int due, taken;

  /// One entry per dose not taken: the reason chosen, or null when the
  /// dose was never recorded.
  final List<SkipReason?> missedReasons;

  DayStatus get status => due == 0
      ? DayStatus.none
      : taken == due
      ? DayStatus.taken
      : taken == 0
      ? DayStatus.missed
      : DayStatus.partial;
}

@immutable
class CourseAdherence {
  const CourseAdherence(this.course, this.days);
  final MedicationCourse course;
  final List<DayAdherence> days;

  int get dueDoses => days.fold(0, (sum, d) => sum + d.due);
  int get takenDoses => days.fold(0, (sum, d) => sum + d.taken);
  int get missedDoses => dueDoses - takenDoses;

  /// Null when nothing was due in the period.
  int? get percent =>
      dueDoses == 0 ? null : (takenDoses * 100 / dueDoses).round();
  AdherenceLevel? get level => switch (percent) {
    final int p => AdherenceLevel.of(p),
    null => null,
  };

  /// Doses not taken, by reason label, most frequent first.
  List<(String, int)> get missedByReason {
    final counts = <String, int>{};
    for (final day in days) {
      for (final reason in day.missedReasons) {
        final label = reason?.label ?? unrecordedLabel;
        counts[label] = (counts[label] ?? 0) + 1;
      }
    }
    return counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Plain statements computed from the log, never a reading of the
  /// person's health. Shown under the strip so the doctor does not have to
  /// count cells.
  List<String> get facts {
    if (dueDoses == 0) return const ['Chưa có liều nào đến giờ trong kỳ này.'];
    if (missedDoses == 0) {
      return ['Không bỏ liều nào trong ${days.length} ngày.'];
    }
    final (topReason, topCount) = missedByReason.first;
    final out = [
      'Bỏ $missedDoses liều, nhiều nhất vì “$topReason” ($topCount lần).',
    ];
    if (days.length > recentDays) {
      final recentStart = days[days.length - recentDays].day;
      for (final reason in SkipReason.values) {
        if (reason == SkipReason.forgot) continue;
        final hits = [
          for (final day in days)
            for (final r in day.missedReasons)
              if (r == reason) day.day,
        ];
        if (hits.length >= 3 &&
            hits.every((d) => d.compareTo(recentStart) >= 0)) {
          out.add(
            'Cả ${hits.length} lần chọn “${reason.label}” đều trong '
            '$recentDays ngày gần nhất (từ ${_short(recentStart)}).',
          );
        }
      }
    }
    return out;
  }

  /// Window in which a cluster of the same reason is pointed out.
  static const recentDays = 14;

  static String _short(String day) =>
      '${day.substring(8, 10)}/${day.substring(5, 7)}';
}

/// Adherence of [course] over [days] days starting on [from]. A dose counts
/// once it is past its time by [missedAfter] or has been recorded, the same
/// rule the Today list uses, so the patient and the doctor see one number.
CourseAdherence adherenceOf(
  MedicationCourse course,
  Map<String, DoseLogEntry> log, {
  required DateTime from,
  required int days,
  required DateTime now,
}) {
  final start = dayOf(from);
  return CourseAdherence(course, [
    for (var i = 0; i < days; i++)
      _day(course, log, start.add(Duration(days: i)), now),
  ]);
}

DayAdherence _day(
  MedicationCourse course,
  Map<String, DoseLogEntry> log,
  DateTime day,
  DateTime now,
) {
  var due = 0, taken = 0;
  final missed = <SkipReason?>[];
  for (final dose in course.item.doses) {
    final at = course.timeOn(day, dose);
    if (at == null) continue;
    final entry = log[doseKey(course.id, dayKey(day), dose.slot)];
    final state = stateOf(at, entry, now);
    if (state == DoseState.upcoming || state == DoseState.due) continue;
    due++;
    if (state == DoseState.taken) {
      taken++;
    } else {
      missed.add(entry?.reason);
    }
  }
  return DayAdherence(
    day: dayKey(day),
    due: due,
    taken: taken,
    missedReasons: List.unmodifiable(missed),
  );
}

/// Taken over due across several courses, for the worklist column.
int? overallPercent(Iterable<CourseAdherence> courses) {
  final due = courses.fold(0, (sum, c) => sum + c.dueDoses);
  if (due == 0) return null;
  final taken = courses.fold(0, (sum, c) => sum + c.takenDoses);
  return (taken * 100 / due).round();
}
