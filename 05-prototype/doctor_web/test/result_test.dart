import 'dart:io';

import 'package:doctor_web/data/models.dart';
import 'package:doctor_web/features/result/rx_pdf.dart';
import 'package:doctor_web/features/result/rx_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_core/medic_core.dart';

import 'doctor_web_test.dart' show pumpApp;
import 'fixtures.dart';

Future<void> openResultTab(WidgetTester tester) async {
  await tester.tap(find.text('Phạm Thị Lan'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kết quả & đơn thuốc'));
  await tester.pumpAndSettle();
}

/// Lets the autosave debounce fire and the save finish.
Future<void> settleSave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('kê đơn: dùng lại đơn cũ, thêm chẩn đoán, tự lưu, ký gửi', (
    tester,
  ) async {
    final backend = await pumpApp(tester);
    await openResultTab(tester);

    expect(find.textContaining('Chưa kê thuốc'), findsOneWidget);
    final send = find.widgetWithText(FilledButton, 'Ký và gửi kết quả');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    expect(find.textContaining('Chưa có chẩn đoán.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Gút (M10)'));
    await tester.tap(find.text('Dùng lại đơn 20/10/2026'));
    await settleSave(tester);

    expect(find.text('SL: 30 viên'), findsNWidgets(2));
    expect(backend.calls, contains('PUT /v1/appointments/a-p2/result-draft'));
    expect(backend.result!['diagnosis'], [
      ['M10', 'Gút'],
    ]);
    expect((backend.result!['items']! as List).length, 2);
    expect(find.textContaining('Đã lưu nháp lúc 08:45'), findsOneWidget);

    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Gửi');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('Tôi đã kiểm tra chẩn đoán và đơn thuốc.'));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(backend.calls, contains('POST /v1/appointments/a-p2/result/send'));
    expect(find.text('Đã gửi kết quả'), findsOneWidget);
    expect(find.text('K7MQ-4XR2-9D'), findsOneWidget);
    expect(
      find.text('Mã nhận kết quả trên MedicApp: K7MQ-4XR2-9D'),
      findsOneWidget,
    );
    expect(find.text('In đơn thuốc'), findsOneWidget);

    await tester.tap(find.text('Sửa kết quả'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Đổi liều');
    await tester.pump();
    await tester.tap(find.text('Mở bản sửa'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('POST /v1/appointments/a-p2/result/amend'));
    expect(
      find.textContaining('Đang sửa kết quả đã gửi (bản 2)'),
      findsOneWidget,
    );
    expect(find.text('Gửi bản sửa'), findsOneWidget);
  });

  testWidgets(
    'dòng thuốc: chọn từ danh mục, liều theo buổi, tự tính số lượng',
    (tester) async {
      await pumpApp(tester);
      await openResultTab(tester);

      await tester.tap(find.text('Thêm thuốc'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Tên thuốc'),
        'colch',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Colchicin 1mg'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Thêm sáng'));
      await tester.tap(find.byTooltip('Thêm tối'));
      await tester.pump();
      await tester.tap(find.byTooltip('Thêm tối'));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '7'));
      await tester.tap(find.widgetWithText(ChoiceChip, '7'));
      await tester.pump();

      // 1 + 1,5 = 2,5 viên/ngày × 7 ngày = 17,5 → 18 viên.
      expect(find.text('Số lượng (tự tính: liều × ngày)'), findsOneWidget);
      expect(find.widgetWithText(TextField, '18'), findsOneWidget);
      expect(find.textContaining('Trên đơn:'), findsOneWidget);
      expect(
        find.textContaining('Ngày uống 2 lần, sáng 1 viên, tối'),
        findsOneWidget,
      );

      await tester.tap(find.text('Xong'));
      await settleSave(tester);
      expect(find.text('Colchicin 1mg'), findsOneWidget);
      expect(find.text('SL: 18 viên'), findsOneWidget);
    },
  );

  test('PDF đơn thuốc: A4, một trang, có lời dặn và mã nhận', () async {
    final staff = StaffSession.fromJson(session);
    final chart = ChartData.fromJson(chartLan);
    final sheet = RxSheet.of(
      chart: chart,
      session: staff,
      diagnosis: const [('M10', 'Gút')],
      items: chart.lastVisit!.items,
      advice: 'Uống đủ 2 lít nước mỗi ngày.',
      followUpDate: '2026-12-03',
      claimCode: 'K7MQ-4XR2-9D',
    );
    expect(sheet.advice.last, 'Hẹn tái khám ngày 03/12/2026.');
    expect(sheet.doctorName, 'Nguyễn Thu Hà');
    expect(rxFileName(sheet), startsWith('don-thuoc-pham-thi-lan-'));

    final bytes = await buildRxPdf(
      sheet,
      load: (path) async =>
          ByteData.sublistView(await File(path).readAsBytes()),
    );
    final raw = String.fromCharCodes(bytes);
    expect(raw.startsWith('%PDF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, 1);
  });

  test('cách dùng in trên đơn ghép thêm ghi chú', () {
    const item = PrescriptionItem(
      name: 'Allopurinol',
      strength: '300mg',
      form: 'viên',
      route: 'Uống',
      quantity: 30,
      doses: [Dose(DoseSlot.morning, 1)],
      meal: MealTiming.after,
      days: 30,
      note: 'Uống nhiều nước',
    );
    expect(RxSheet.usage(item), endsWith('. Uống nhiều nước'));
  });
}
