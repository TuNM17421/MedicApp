import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/visit_prep/visit_prep.dart';
import 'package:medic_app/features/visit_prep/visit_prep_catalog.dart';

import '../app_navigation_test.dart' show openApp, tapTab, tapText;

VisitSummary visit({
  String patientId = 'self',
  String departmentId = 'endocrine',
  String departmentName = 'Nội tiết',
  DateTime? date,
  String time = '08:00',
  String id = 'V1',
}) => VisitSummary(
  id: id,
  patientName: 'Phạm Văn Hòa',
  type: VisitType.service,
  facilityName: 'Phòng khám Đa khoa An Bình',
  address: '12 đường Hoa Sữa',
  departmentName: departmentName,
  doctorName: 'BS. Nguyễn Thu Hà',
  date: date ?? DateTime(2026, 10, 16),
  time: time,
  fee: 250000,
  method: PayMethod.atHospital,
  contactName: 'Phạm Văn Hòa',
  contactPhone: '0900000123',
  note: '',
  patientId: patientId,
  departmentId: departmentId,
);

const receipt = PaymentReceipt(
  status: PaymentStatus.confirmed,
  method: PayMethod.atHospital,
  appointmentCode: 'MA123',
);

void main() {
  final evening = DateTime(2026, 10, 15, 19, 30);
  final self = demoProfiles[0];
  final mother = demoProfiles[1];

  test('fasting blood sugar visit tomorrow morning, in the user\'s words', () {
    final notes = adviseVisit(visit: visit(), patient: self, now: evening);
    expect(notes, hasLength(1));
    final note = notes.single;
    expect(note.condition.id, 'diabetes');
    expect(
      note.headline,
      'Bạn có lịch khám Nội tiết lúc 08:00 sáng mai. Vì đang theo dõi '
      'đái tháo đường, bác sĩ có thể cho xét nghiệm đường huyết lúc đói: '
      'vui lòng nhịn ăn từ nửa đêm nay (8 tiếng trước).',
    );
    final texts = note.items.map((item) => item.text).toList();
    expect(texts.first, startsWith('Ăn bữa cuối trước nửa đêm nay.'));
    expect(texts, contains(contains('hỏi bác sĩ trước về thuốc tiểu đường')));
  });

  test('heart visit gives blood pressure advice and no lipid advice '
      'when the patient is not followed for it', () {
    final notes = adviseVisit(
      visit: visit(departmentId: 'heart', departmentName: 'Tim mạch'),
      patient: self,
      now: evening,
    );
    expect(notes.map((n) => n.condition.id), ['hypertension']);
    expect(notes.single.headline, contains('không hút thuốc'));
  });

  test('a relative is named, alcohol deadline counts back 24 hours', () {
    final notes = adviseVisit(
      visit: visit(
        patientId: 'mother',
        departmentId: 'bones',
        departmentName: 'Cơ Xương Khớp',
        date: DateTime(2026, 10, 17),
        time: '14:30',
      ),
      patient: mother,
      now: evening,
    );
    final note = notes.single;
    expect(note.headline, startsWith('Mẹ Phạm Thị Lan (78 tuổi) có lịch khám'));
    expect(note.headline, contains('14:30 chiều Thứ Bảy 17/10'));
    expect(
      note.items.map((i) => i.text),
      contains('Không uống rượu bia từ 14:30 chiều mai (24 tiếng trước).'),
    );
  });

  test('a deadline already passed tells the patient what to do now', () {
    final notes = adviseVisit(
      visit: visit(date: DateTime(2026, 10, 15), time: '20:00'),
      patient: self,
      now: evening,
    );
    expect(
      notes.single.items.first.text,
      'Nếu bạn chưa ăn gì từ 12:00 trưa nay thì đã đủ 8 tiếng. Nếu đã ăn, '
      'hãy báo nhân viên khi đến khám.',
    );
  });

  test('endoscopy: water cutoff and someone to take an older patient home', () {
    final notes = adviseVisit(
      visit: visit(departmentId: 'general', departmentName: 'Nội tổng quát'),
      patient: self.withConditions(['gastritis']),
      now: evening,
    );
    final texts = notes.single.items.map((i) => i.text);
    expect(
      texts,
      contains('Ngừng uống mọi thứ, kể cả nước lọc, từ 06:00 sáng mai.'),
    );
    expect(texts, contains(contains('không tự lái xe về')));
  });

  test('no advice for past visits, other departments or no conditions', () {
    expect(
      adviseVisit(visit: visit(), patient: self, now: DateTime(2026, 10, 17)),
      isEmpty,
    );
    expect(
      adviseVisit(
        visit: visit(departmentId: 'eyes', departmentName: 'Mắt'),
        patient: self,
        now: evening,
      ),
      isEmpty,
    );
    expect(
      adviseVisit(
        visit: visit(),
        patient: self.withConditions(const []),
        now: evening,
      ),
      isEmpty,
    );
  });

  test('every condition has sources and a department in the catalog', () {
    expect(VisitPrepCatalog.conditions, hasLength(5));
    for (final condition in VisitPrepCatalog.conditions) {
      expect(condition.sources, isNotEmpty, reason: condition.id);
      for (final source in condition.sources) {
        expect(source.url, startsWith('https://'));
      }
    }
  });

  testWidgets('home shows the soonest note; detail shows the full plan; '
      'unticking the condition removes it', (tester) async {
    final c = await openApp(
      tester,
      size: const Size(412, 915),
      overrides: [prepClockProvider.overrideWithValue(() => evening)],
    );
    c
        .read(appointmentsProvider.notifier)
        .upsert(AppointmentRecord(visit(), receipt));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-prep')), findsOneWidget);
    expect(find.textContaining('nhịn ăn từ nửa đêm nay'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-prep')));
    await tester.pumpAndSettle();
    expect(find.text('Chuẩn bị trước khi khám'), findsOneWidget);
    expect(find.text('Xét nghiệm đường huyết lúc đói'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tapTab(tester, 'Hồ sơ');
    await tapText(tester, 'Xem hồ sơ đang chọn');
    final chip = find.byKey(const ValueKey('condition-diabetes'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(c.read(profileCatalogProvider).first.conditions, ['hypertension']);
    expect(c.read(visitPrepNotesProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
