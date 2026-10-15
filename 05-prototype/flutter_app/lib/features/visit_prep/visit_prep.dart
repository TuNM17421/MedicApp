import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_state.dart';
import '../booking/application/booking_providers.dart';
import '../booking/domain/booking_models.dart';
import 'visit_prep_catalog.dart';

/// Current time in Vietnam as a naive local value, matching appointment dates.
final prepClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc().add(const Duration(hours: 7)),
);

class PrepItem {
  const PrepItem(this.text, {this.important = false});
  final String text;

  /// Timed or safety items, drawn more prominently.
  final bool important;
}

/// Preparation for one upcoming visit, written for this patient.
class VisitPrepNote {
  const VisitPrepNote({
    required this.visitId,
    required this.condition,
    required this.headline,
    required this.items,
  });
  final String visitId;
  final PrepCondition condition;

  /// One sentence naming who, which visit, when and the main thing to do.
  final String headline;
  final List<PrepItem> items;
}

/// Rule-based "AI" reading the profile and the appointment. Nothing is sent
/// anywhere; it only combines the patient's conditions, the visit time and
/// [VisitPrepCatalog].
List<VisitPrepNote> adviseVisit({
  required VisitSummary visit,
  required PreviewProfile? patient,
  required DateTime now,
}) {
  final start = visitStart(visit);
  if (patient == null || visit.departmentId == null || !start.isAfter(now)) {
    return const [];
  }
  final matches = [
    for (final id in patient.conditions)
      if (VisitPrepCatalog.byId(id) case final condition?
          when condition.departmentIds.contains(visit.departmentId))
        condition,
  ];
  final self = patient.relationship == selfRelationship;
  final who = prepWho(patient, now);
  final hasDiabetes = patient.conditions.contains('diabetes');
  return [
    for (final condition in matches)
      VisitPrepNote(
        visitId: visit.id,
        condition: condition,
        headline: _headline(who, visit, condition, start, now),
        items: [
          ..._timedItems(condition, start, now),
          if (hasDiabetes && (condition.fastingHours != null))
            PrepItem(
              '${self ? 'Bạn' : who} đang theo dõi đái tháo đường: hỏi bác sĩ '
              'trước về thuốc tiểu đường hoặc insulin trong lúc nhịn ăn. '
              'Không tự ý bỏ hay đổi thuốc.',
              important: true,
            ),
          if (condition.sedation)
            PrepItem(
              patient.birthYear <= now.year - 60
                  ? 'Nếu nội soi có gây mê, cần người nhà đi cùng để đưa về; '
                        'không tự lái xe về.'
                  : 'Nếu nội soi có gây mê, nên có người nhà đi cùng để đưa về.',
              important: true,
            ),
          ..._audienceItems(patient, condition, now),
          for (final step in condition.steps) PrepItem(step),
        ],
      ),
  ];
}

int ageOf(PreviewProfile patient, DateTime now) {
  final birth = patient.birthDate;
  if (birth == null) return now.year - patient.birthYear;
  final hadBirthday =
      now.month > birth.month ||
      (now.month == birth.month && now.day >= birth.day);
  return now.year - birth.year - (hadBirthday ? 0 : 1);
}

bool isChild(PreviewProfile patient, DateTime now) => ageOf(patient, now) < 16;

bool isOlder(PreviewProfile patient, DateTime now) => ageOf(patient, now) >= 60;

/// "Bạn", "Mẹ Phạm Thị Lan (78 tuổi)", "Cháu Phạm Minh An (9 tuổi)".
String prepWho(PreviewProfile patient, DateTime now) {
  if (patient.relationship == selfRelationship) return 'Bạn';
  final age = ageOf(patient, now);
  final showAge = isChild(patient, now) || isOlder(patient, now);
  return '${patient.relationship} ${patient.name}${showAge ? ' ($age tuổi)' : ''}';
}

/// Advice that depends on who the patient is rather than on the condition.
List<PrepItem> _audienceItems(
  PreviewProfile patient,
  PrepCondition condition,
  DateTime now,
) {
  final fasting = condition.fastingHours != null;
  final age = ageOf(patient, now);
  return [
    if (isChild(patient, now) && fasting)
      const PrepItem(
        'Trẻ nhỏ khó nhịn lâu: người lớn nhắc và trông bé trong lúc nhịn, '
        'hỏi bác sĩ thời gian nhịn phù hợp với tuổi của bé.',
        important: true,
      ),
    if (isOlder(patient, now) && !condition.sedation)
      const PrepItem(
        'Nên có người nhà đi cùng. Mang theo thuốc đang dùng và kính đọc '
        'sách nếu có.',
      ),
    if (isOlder(patient, now) && fasting)
      const PrepItem(
        'Nếu thấy mệt, chóng mặt hay vã mồ hôi trong lúc nhịn, hãy báo ngay '
        'cho người nhà hoặc nhân viên y tế.',
        important: true,
      ),
    if (patient.gender == 'Nữ' &&
        age >= 15 &&
        age <= 49 &&
        (fasting || condition.sedation))
      const PrepItem(
        'Nếu đang mang thai hoặc cho con bú, báo bác sĩ trước khi nhịn ăn '
        'hay làm thủ thuật.',
      ),
  ];
}

DateTime visitStart(VisitSummary visit) {
  final [hour, minute] = visit.time.split(':').map(int.parse).toList();
  return DateTime(
    visit.date.year,
    visit.date.month,
    visit.date.day,
    hour,
    minute,
  );
}

String _headline(
  String who,
  VisitSummary visit,
  PrepCondition condition,
  DateTime start,
  DateTime now,
) {
  final when = '${prepClock(start)} ${prepDayPart(start, now)}';
  final main = condition.fastingHours != null
      ? 'vui lòng nhịn ăn từ ${prepMoment(start.subtract(Duration(hours: condition.fastingHours!)), now)} '
            '(${condition.fastingHours} tiếng trước)'
      : condition.noSmokeCaffeineMinutes != null
      ? 'không hút thuốc, không uống cà phê hay trà trong '
            '${condition.noSmokeCaffeineMinutes} phút trước khi đo'
      : 'xem chuẩn bị bên dưới';
  return '$who có lịch khám ${visit.departmentName} lúc $when. '
      'Vì đang theo dõi ${condition.name}, bác sĩ có thể cho '
      '${condition.visitLabel}: $main.';
}

List<PrepItem> _timedItems(
  PrepCondition condition,
  DateTime start,
  DateTime now,
) => [
  if (condition.fastingHours case final hours?)
    _deadlineItem(
      start.subtract(Duration(hours: hours)),
      now,
      upcoming: (at) =>
          'Ăn bữa cuối trước $at. Sau đó nhịn ăn ít nhất $hours tiếng, '
          'chỉ uống nước lọc.',
      passed: (at) =>
          'Nếu bạn chưa ăn gì từ $at thì đã đủ $hours tiếng. Nếu đã ăn, '
          'hãy báo nhân viên khi đến khám.',
    ),
  if (condition.liquidStopHours case final hours?)
    _deadlineItem(
      start.subtract(Duration(hours: hours)),
      now,
      upcoming: (at) => 'Ngừng uống mọi thứ, kể cả nước lọc, từ $at.',
      passed: (at) => 'Ngừng uống mọi thứ, kể cả nước lọc, từ bây giờ.',
    ),
  if (condition.noAlcoholHours case final hours?)
    _deadlineItem(
      start.subtract(Duration(hours: hours)),
      now,
      upcoming: (at) => 'Không uống rượu bia từ $at ($hours tiếng trước).',
      passed: (at) =>
          'Không uống rượu bia từ giờ đến lúc khám. Nếu đã uống trong '
          '$hours tiếng qua, hãy báo bác sĩ.',
    ),
  if (condition.noSmokeCaffeineMinutes case final minutes?)
    PrepItem(
      'Không hút thuốc, không uống cà phê hay trà trong $minutes phút '
      'trước khi đo huyết áp.',
      important: true,
    ),
];

PrepItem _deadlineItem(
  DateTime at,
  DateTime now, {
  required String Function(String at) upcoming,
  required String Function(String at) passed,
}) => PrepItem(
  at.isAfter(now) ? upcoming(prepMoment(at, now)) : passed(prepMoment(at, now)),
  important: true,
);

String prepClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// "20:00 tối nay", "nửa đêm nay", "08:00 sáng mai".
String prepMoment(DateTime time, DateTime now) {
  if (time.hour == 0 && time.minute == 0) {
    final eve = time.subtract(const Duration(days: 1));
    return 'nửa đêm ${_dayWord(eve, now)}';
  }
  return '${prepClock(time)} ${prepDayPart(time, now)}';
}

String prepDayPart(DateTime time, DateTime now) {
  final part = switch (time.hour) {
    < 5 => 'rạng sáng',
    < 11 => 'sáng',
    < 13 => 'trưa',
    < 18 => 'chiều',
    _ => 'tối',
  };
  return '$part ${_dayWord(time, now)}';
}

String _dayWord(DateTime time, DateTime now) {
  final days = DateTime(
    time.year,
    time.month,
    time.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'nay';
  if (days == 1) return 'mai';
  if (days == -1) return 'qua';
  const weekdays = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  return '${weekdays[time.weekday - 1]} '
      '${time.day.toString().padLeft(2, '0')}/'
      '${time.month.toString().padLeft(2, '0')}';
}

/// Notes for every upcoming, not failed appointment, soonest first.
final visitPrepNotesProvider = Provider<List<VisitPrepNote>>((ref) {
  final profiles = ref.watch(profileCatalogProvider);
  final now = ref.watch(prepClockProvider)();
  final records = [
    ...ref
        .watch(appointmentsProvider)
        .records
        .where((record) => record.receipt.status != PaymentStatus.failed),
  ]..sort((a, b) => visitStart(a.visit).compareTo(visitStart(b.visit)));
  return [
    for (final record in records)
      ...adviseVisit(
        visit: record.visit,
        patient: profiles
            .where((profile) => profile.id == record.visit.patientId)
            .firstOrNull,
        now: now,
      ),
  ];
});
