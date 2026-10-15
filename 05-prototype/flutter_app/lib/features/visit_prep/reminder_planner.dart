import '../../app/state/app_state.dart';
import '../booking/domain/booking_models.dart';
import 'visit_prep.dart';

enum ReminderKind {
  /// Two days ahead, for restrictions of 24 hours or more (alcohol).
  advance,

  /// Before the shorter restrictions start, or a plain visit reminder.
  prepare,

  /// Shortly before leaving home.
  leave,
}

extension ReminderKindLabel on ReminderKind {
  String get label => switch (this) {
    ReminderKind.advance => 'Nhắc sớm',
    ReminderKind.prepare => 'Nhắc chuẩn bị',
    ReminderKind.leave => 'Nhắc trước khi đi',
  };
}

class PlannedReminder {
  const PlannedReminder({
    required this.visitId,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
  });
  final String visitId;
  final ReminderKind kind;

  /// Vietnam local time, like appointment times.
  final DateTime at;
  final String title;

  /// Full text for the expanded notification; the first sentence is what a
  /// collapsed notification shows.
  final String body;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.visitId == visitId &&
      other.kind == kind &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(visitId, kind, at, title, body);
}

/// Morning visits are reminded the day before so there is time to prepare;
/// afternoon visits can be reminded early the same morning.
const _sameDayMorning = 7;
const _dayBeforeAfternoon = 17;
const _dayBeforeMorning = 8;
const _advanceHour = 9;
const _earliestHour = 6;

/// Picks when to remind about one visit. Rules, in plain words:
/// - A restriction of 24 hours or more (no alcohol) gets a reminder at 09:00
///   the day before it starts, i.e. about two days before the visit.
/// - Shorter restrictions (fasting, no water, no coffee) get a reminder at the
///   latest of 07:00 the same day (afternoon visits only), 17:00 the day
///   before or 08:00 the day before that still falls at least an hour before
///   the restriction starts.
/// - A last reminder two hours before the visit, never before 06:00.
/// Times already past are dropped; a restriction that has not started yet but
/// whose slot has passed is reminded right away.
List<PlannedReminder> planReminders({
  required VisitSummary visit,
  required PreviewProfile? patient,
  required List<VisitPrepNote> notes,
  required DateTime now,
}) {
  final start = visitStart(visit);
  if (!start.isAfter(now)) return const [];
  final who = patient == null ? visit.patientName : prepWho(patient, now);
  final whenVisit = '${prepClock(start)} ${prepDayPart(start, now)}';
  final day = DateTime(start.year, start.month, start.day);
  DateTime at(DateTime date, int hour) =>
      DateTime(date.year, date.month, date.day, hour);
  final soon = now.add(const Duration(minutes: 1));

  final longLeads = [
    for (final note in notes)
      if ((note.condition.noAlcoholHours ?? 0) >= 24)
        (hours: note.condition.noAlcoholHours!, note: note),
  ];
  final shortMinutes = [
    for (final note in notes) ...[
      if (note.condition.fastingHours case final h?) h * 60,
      if (note.condition.liquidStopHours case final h?) h * 60,
      ?note.condition.noSmokeCaffeineMinutes,
    ],
  ];

  final result = <PlannedReminder>[];

  if (longLeads.isNotEmpty) {
    final hours = longLeads
        .map((lead) => lead.hours)
        .reduce((a, b) => a > b ? a : b);
    final from = start.subtract(Duration(hours: hours));
    var time = at(from.subtract(const Duration(days: 1)), _advanceHour);
    if (!time.isAfter(now) && from.isAfter(now)) time = soon;
    if (time.isAfter(now)) {
      final labels = longLeads
          .map((lead) => lead.note.condition.visitLabel)
          .toSet()
          .join(', ');
      result.add(
        PlannedReminder(
          visitId: visit.id,
          kind: ReminderKind.advance,
          at: time,
          title: 'Sắp đến lịch khám: chuẩn bị từ sớm',
          body:
              '$who có lịch khám ${visit.departmentName} lúc $whenVisit. '
              'Để $labels chính xác, không uống rượu bia từ '
              '${prepMoment(from, now)} ($hours tiếng trước giờ khám).',
        ),
      );
    }
  }

  final restrictionStart = shortMinutes.isEmpty
      ? start
      : start.subtract(
          Duration(minutes: shortMinutes.reduce((a, b) => a > b ? a : b)),
        );
  final deadline = restrictionStart.subtract(const Duration(hours: 1));
  final previous = day.subtract(const Duration(days: 1));
  final candidates = [
    if (start.hour >= 12) at(day, _sameDayMorning),
    at(previous, _dayBeforeAfternoon),
    at(previous, _dayBeforeMorning),
  ];
  var prepareAt = candidates
      .where((time) => !time.isAfter(deadline) && time.isAfter(now))
      .firstOrNull;
  if (prepareAt == null && notes.isNotEmpty && restrictionStart.isAfter(now)) {
    prepareAt = soon;
  }
  if (prepareAt != null) {
    result.add(
      PlannedReminder(
        visitId: visit.id,
        kind: ReminderKind.prepare,
        at: prepareAt,
        title: notes.isEmpty
            ? 'Nhắc lịch khám'
            : 'Chuẩn bị khám: ${notes.first.condition.visitLabel}',
        body: notes.isEmpty
            ? '$who có lịch khám ${visit.departmentName} lúc $whenVisit tại '
                  '${visit.facilityName}.'
            : {
                for (final note in notes) note.headline,
                for (final item in notes.expand((note) => note.items))
                  if (item.important) item.text,
              }.join(' '),
      ),
    );
  }

  var leaveAt = start.subtract(const Duration(hours: 2));
  if (leaveAt.isBefore(at(day, _earliestHour))) {
    leaveAt = at(day, _earliestHour);
  }
  if (leaveAt.isAfter(now) &&
      leaveAt.isBefore(start) &&
      (prepareAt == null || leaveAt.isAfter(prepareAt))) {
    final older = patient != null && isOlder(patient, now);
    final child = patient != null && isChild(patient, now);
    final sedation = notes.any((note) => note.condition.sedation);
    result.add(
      PlannedReminder(
        visitId: visit.id,
        kind: ReminderKind.leave,
        at: leaveAt,
        title: 'Lịch khám lúc ${prepClock(start)}',
        body: [
          '$who khám ${visit.departmentName} lúc ${prepClock(start)} tại '
              '${visit.facilityName}, ${visit.address}.',
          'Mang giấy tờ tùy thân'
              '${visit.type == VisitType.insurance ? ', thẻ BHYT' : ''}'
              '${notes.isNotEmpty ? ' và thuốc đang dùng' : ''}.',
          if (child) 'Người lớn đưa bé đi và mang theo sổ khám của bé.',
          if (older && !sedation) 'Nên có người nhà đi cùng.',
          if (sedation) 'Nhớ có người nhà đưa về nếu nội soi có gây mê.',
        ].join(' '),
      ),
    );
  }
  return result;
}
