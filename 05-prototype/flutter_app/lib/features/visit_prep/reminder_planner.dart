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

/// One line of the expanded notification: a bold [label] (a time, "Nơi
/// khám", "Lưu ý") followed by plain [text].
class ReminderLine {
  const ReminderLine(this.label, this.text);
  final String label;
  final String text;

  String get plain => '$label: $text';

  @override
  bool operator ==(Object other) =>
      other is ReminderLine && other.label == label && other.text == text;

  @override
  int get hashCode => Object.hash(label, text);
}

/// A phone notification, laid out the way Android shows it:
/// - collapsed: [header] next to the app name, then [title] and [summary];
/// - expanded: [title], then [lines], each starting with a bold label.
class PlannedReminder {
  const PlannedReminder({
    required this.visitId,
    required this.kind,
    required this.at,
    required this.visitAt,
    required this.header,
    required this.title,
    required this.summary,
    required this.lines,
  });
  final String visitId;
  final ReminderKind kind;

  /// Vietnam local time, like appointment times.
  final DateTime at;
  final DateTime visitAt;

  /// Whose visit and which department, e.g. "Mẹ Lan · Cơ Xương Khớp".
  final String header;

  /// What to do and when, kept to about 30 characters so it fits one line.
  final String title;

  /// The one line shown under the title before expanding, about 40 characters.
  final String summary;
  final List<ReminderLine> lines;

  /// Everything as plain text, for the in-app list and screen readers.
  String get body => [summary, for (final line in lines) line.plain].join('\n');

  /// Expanded text for Android, with bold labels and line breaks.
  String get html => [
    for (final line in lines)
      '<b>${_escape(line.label)}:</b> ${_escape(line.text)}',
  ].join('<br>');

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.visitId == visitId &&
      other.kind == kind &&
      other.at == at &&
      other.visitAt == visitAt &&
      other.header == header &&
      other.title == title &&
      other.summary == summary &&
      _sameLines(other.lines, lines);

  @override
  int get hashCode => Object.hash(
    visitId,
    kind,
    at,
    visitAt,
    header,
    title,
    summary,
    Object.hashAll(lines),
  );
}

bool _sameLines(List<ReminderLine> a, List<ReminderLine> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// Morning visits are reminded the day before so there is time to prepare;
/// afternoon visits can be reminded early the same morning.
const _sameDayMorning = 7;
const _dayBeforeAfternoon = 17;
const _dayBeforeMorning = 8;
const _advanceHour = 9;
const _earliestHour = 6;

/// One timed step before the visit, e.g. stop eating at midnight.
typedef _Step = ({DateTime at, String action, String title});

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
  final day = DateTime(start.year, start.month, start.day);
  DateTime at(DateTime date, int hour) =>
      DateTime(date.year, date.month, date.day, hour);
  final soon = now.add(const Duration(minutes: 1));
  final conditions = [for (final note in notes) note.condition];
  int? longest(Iterable<int?> values) {
    final present = values.whereType<int>();
    return present.isEmpty ? null : present.reduce((a, b) => a > b ? a : b);
  }

  final alcoholHours = longest(conditions.map((c) => c.noAlcoholHours));
  final fastingHours = longest(conditions.map((c) => c.fastingHours));
  final liquidHours = longest(conditions.map((c) => c.liquidStopHours));
  final smokeMinutes = longest(conditions.map((c) => c.noSmokeCaffeineMinutes));
  final sedation = conditions.any((c) => c.sedation);
  final older = patient != null && isOlder(patient, now);
  final child = patient != null && isChild(patient, now);
  final labels = conditions.map((c) => c.visitLabel).toSet().join(', ');

  final self = patient?.relationship == selfRelationship;
  final shortName = patient == null
      ? visit.patientName
      : self
      ? 'Lịch của bạn'
      : '${patient.relationship} ${patient.name.split(' ').last}';
  final header = '$shortName · ${visit.departmentName}';
  final whoVisits = patient == null
      ? '${visit.patientName} khám'
      : self
      ? 'Khám'
      : '${prepWho(patient, now)} khám';

  final steps = <_Step>[
    if (alcoholHours != null)
      (
        at: start.subtract(Duration(hours: alcoholHours)),
        action: 'Không uống rượu bia',
        title: 'Kiêng rượu bia',
      ),
    if (fastingHours != null)
      (
        at: start.subtract(Duration(hours: fastingHours)),
        action: 'Ngừng ăn, chỉ uống nước lọc',
        title: 'Nhịn ăn',
      ),
    if (liquidHours != null)
      (
        at: start.subtract(Duration(hours: liquidHours)),
        action: 'Ngừng uống, kể cả nước lọc',
        title: 'Ngừng uống',
      ),
    if (smokeMinutes != null)
      (
        at: start.subtract(Duration(minutes: smokeMinutes)),
        action: 'Không cà phê, trà, thuốc lá',
        title: 'Kiêng cà phê, thuốc lá',
      ),
  ]..sort((a, b) => a.at.compareTo(b.at));

  /// Advice for this patient, most important first, kept short.
  List<ReminderLine> tips({required bool leaving}) => [
    for (final text in [
      if (sedation)
        child
            ? 'Nếu bé được gây mê, cần người lớn đưa về và trông bé.'
            : 'Cần người nhà đi cùng để đưa về, không tự lái xe.',
      if (!leaving &&
          fastingHours != null &&
          (patient?.conditions.contains('diabetes') ?? false))
        'Hỏi bác sĩ về thuốc tiểu đường khi nhịn ăn, không tự bỏ thuốc.',
      if (child && leaving) 'Người lớn đưa bé đi, mang sổ khám của bé.',
      if (child && !leaving && fastingHours != null)
        'Người lớn trông bé trong lúc nhịn, bé khó nhịn lâu.',
      if (older && !sedation && leaving) 'Nên có người nhà đi cùng.',
      if (older && !leaving && fastingHours != null)
        'Nếu chóng mặt, vã mồ hôi khi nhịn, báo ngay người nhà.',
      if (!leaving &&
          patient?.gender == 'Nữ' &&
          patient != null &&
          ageOf(patient, now) >= 15 &&
          ageOf(patient, now) <= 49 &&
          (fastingHours != null || sedation))
        'Nếu đang mang thai hoặc cho con bú, báo bác sĩ trước.',
    ].take(2))
      ReminderLine('Lưu ý', text),
  ];

  ReminderLine stepLine(_Step step, DateTime when) => step.at.isAfter(when)
      ? ReminderLine(_capitalised(prepMoment(step.at, when)), step.action)
      : ReminderLine('Đang kiêng', '${step.action} đến lúc khám');
  ReminderLine visitLine(DateTime when) => ReminderLine(
    _capitalised('${prepClock(start)} ${prepDayPart(start, when)}'),
    '$whoVisits tại ${visit.facilityName}',
  );
  final why = labels.isEmpty
      ? null
      : ReminderLine('Để chuẩn bị', labels);

  final result = <PlannedReminder>[];

  if (alcoholHours != null && alcoholHours >= 24) {
    final from = start.subtract(Duration(hours: alcoholHours));
    var time = at(from.subtract(const Duration(days: 1)), _advanceHour);
    if (!time.isAfter(now) && from.isAfter(now)) time = soon;
    if (time.isAfter(now)) {
      final alcohol = steps.firstWhere(
        (step) => step.title == 'Kiêng rượu bia',
      );
      result.add(
        PlannedReminder(
          visitId: visit.id,
          kind: ReminderKind.advance,
          at: time,
          visitAt: start,
          header: header,
          title: 'Từ ${prepDayPart(from, time)}: kiêng rượu bia',
          summary: 'Trước lịch khám ${prepDayPart(start, time)}',
          lines: [
            stepLine(alcohol, time),
            visitLine(time),
            ?why,
            const ReminderLine('Nếu lỡ uống', 'Báo bác sĩ khi đến khám.'),
          ],
        ),
      );
    }
  }

  final restrictionStart = [
    for (final step in steps)
      if (step.title != 'Kiêng rượu bia' || alcoholHours! < 24) step.at,
  ].fold(start, (a, b) => b.isBefore(a) ? b : a);
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
    final when = prepareAt;
    final visitTime = '${prepClock(start)} ${prepDayPart(start, when)}';
    final headline = steps
        .where((step) => step.at.isAfter(when))
        .where((step) => step.title != 'Kiêng cà phê, thuốc lá')
        .firstOrNull;
    result.add(
      PlannedReminder(
        visitId: visit.id,
        kind: ReminderKind.prepare,
        at: when,
        visitAt: start,
        header: header,
        title: headline != null
            ? '${headline.title} từ ${prepMoment(headline.at, when)}'
            : notes.isEmpty
            ? 'Lịch khám $visitTime'
            : 'Chuẩn bị khám $visitTime',
        summary: headline != null
            ? 'Khám lúc $visitTime'
            : smokeMinutes != null
            ? 'Không cà phê, thuốc lá $smokeMinutes phút trước'
            : visit.facilityName,
        lines: [
          for (final step in steps) stepLine(step, when),
          visitLine(when),
          if (notes.isEmpty) ReminderLine('Địa chỉ', visit.address),
          ?why,
          ...tips(leaving: false),
        ],
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
    final noDrinks =
        liquidHours != null &&
        !start.subtract(Duration(hours: liquidHours)).isAfter(leaveAt);
    result.add(
      PlannedReminder(
        visitId: visit.id,
        kind: ReminderKind.leave,
        at: leaveAt,
        visitAt: start,
        header: header,
        title: 'Khám lúc ${prepClock(start)} ${prepDayPart(start, leaveAt)}',
        summary: visit.facilityName,
        lines: [
          ReminderLine('Nơi khám', '${visit.facilityName}, ${visit.address}'),
          ReminderLine(
            'Mang theo',
            [
              'CCCD',
              if (visit.type == VisitType.insurance) 'thẻ BHYT',
              if (notes.isNotEmpty) 'thuốc đang dùng',
            ].join(', '),
          ),
          if (fastingHours != null)
            ReminderLine(
              'Nhớ',
              noDrinks
                  ? 'Không ăn uống gì đến khi khám xong.'
                  : 'Vẫn nhịn ăn, chỉ uống nước lọc đến khi khám xong.',
            ),
          ...tips(leaving: true),
        ],
      ),
    );
  }
  return result;
}
