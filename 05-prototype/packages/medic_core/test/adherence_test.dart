import 'package:medic_core/medic_core.dart';
import 'package:test/test.dart';

/// Bà Phạm Thị Lan from the doctor web sample data: Atorvastatin 10mg in the
/// evening for 30 days from 20/10, seen on 19/11.
final prescribedAt = DateTime(2026, 10, 20, 8, 30);
final from = DateTime(2026, 10, 20);
final seenAt = DateTime(2026, 11, 19, 8, 30);

MedicationCourse course(List<Dose> doses, {int days = 30}) => MedicationCourse(
  id: 'v1#1',
  profileId: 'p2',
  visitId: 'v1',
  prescribedAt: prescribedAt,
  item: PrescriptionItem(
    name: 'Atorvastatin',
    strength: '10mg',
    form: 'viên',
    quantity: days * doses.length,
    doses: doses,
    days: days,
  ),
);

DoseLogEntry entry(
  String day,
  DoseSlot slot,
  DoseMark mark, [
  SkipReason? reason,
]) => DoseLogEntry(
  courseId: 'v1#1',
  day: day,
  slot: slot,
  mark: mark,
  at: DateTime.parse('${day}T20:00:00'),
  reason: reason,
);

String dayAt(int index) => dayKey(from.add(Duration(days: index)));

void main() {
  group('Atorvastatin của bà Lan', () {
    const skipped = {
      3: SkipReason.forgot,
      7: SkipReason.forgot,
      9: SkipReason.other,
      11: SkipReason.forgot,
      13: SkipReason.forgot,
      16: SkipReason.unwell,
      18: SkipReason.unwell,
      19: SkipReason.forgot,
      21: SkipReason.unwell,
      22: SkipReason.unwell,
      24: SkipReason.forgot,
      26: SkipReason.unwell,
    };
    final c = course(const [Dose(DoseSlot.evening, 1)]);
    final log = {
      for (var i = 0; i < 30; i++)
        if (skipped[i] case final reason?)
          doseKey(c.id, dayAt(i), DoseSlot.evening): entry(
            dayAt(i),
            DoseSlot.evening,
            DoseMark.skipped,
            reason,
          )
        else
          doseKey(c.id, dayAt(i), DoseSlot.evening): entry(
            dayAt(i),
            DoseSlot.evening,
            DoseMark.taken,
          ),
    };
    final result = adherenceOf(c, log, from: from, days: 30, now: seenAt);

    test('18 trên 30 liều là 60%, dưới ngưỡng 80%', () {
      expect(result.dueDoses, 30);
      expect(result.takenDoses, 18);
      expect(result.percent, 60);
      expect(result.level, AdherenceLevel.fair);
    });

    test('đếm lý do bỏ liều, nhiều nhất trước', () {
      expect(result.missedByReason, [
        ('Quên uống', 6),
        ('Thấy khó chịu', 5),
        ('Lý do khác', 1),
      ]);
    });

    test('chỉ ra cụm "Thấy khó chịu" trong 14 ngày gần nhất', () {
      expect(result.facts, [
        'Bỏ 12 liều, nhiều nhất vì “Quên uống” (6 lần).',
        'Cả 5 lần chọn “Thấy khó chịu” đều trong 14 ngày gần nhất (từ 05/11).',
      ]);
    });

    test('mỗi ngày một ô', () {
      expect(result.days, hasLength(30));
      expect(result.days[3].status, DayStatus.missed);
      expect(result.days[4].status, DayStatus.taken);
    });
  });

  test('ngày uống một trong hai liều là uống thiếu', () {
    final c = course(const [
      Dose(DoseSlot.morning, 1),
      Dose(DoseSlot.evening, 1),
    ], days: 3);
    final day = dayAt(1);
    final log = {
      doseKey(c.id, day, DoseSlot.morning): entry(
        day,
        DoseSlot.morning,
        DoseMark.taken,
      ),
    };
    final result = adherenceOf(c, log, from: from, days: 3, now: seenAt);
    // Ngày 20/10: liều sáng trước giờ kê đơn nên không tính.
    expect(result.days[0].due, 1);
    expect(result.days[1].status, DayStatus.partial);
    expect(result.days[1].missedReasons, [null]);
    expect(result.missedByReason.first, (unrecordedLabel, 4));
  });

  test('liều chưa đến giờ không tính', () {
    final c = course(const [Dose(DoseSlot.evening, 1)]);
    final result = adherenceOf(
      c,
      const {},
      from: from,
      days: 1,
      now: DateTime(2026, 10, 20, 18),
    );
    expect(result.dueDoses, 0);
    expect(result.percent, isNull);
    expect(result.days.single.status, DayStatus.none);
    expect(result.facts, ['Chưa có liều nào đến giờ trong kỳ này.']);
  });

  test('tỷ lệ chung cộng dồn số liều của các thuốc', () {
    final good = course(const [Dose(DoseSlot.evening, 1)], days: 2);
    final log = {
      for (var i = 0; i < 2; i++)
        doseKey(good.id, dayAt(i), DoseSlot.evening): entry(
          dayAt(i),
          DoseSlot.evening,
          DoseMark.taken,
        ),
    };
    final a = adherenceOf(good, log, from: from, days: 2, now: seenAt);
    final b = adherenceOf(good, const {}, from: from, days: 2, now: seenAt);
    expect(overallPercent([a, b]), 50);
    expect(overallPercent(const []), isNull);
  });
}
