import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medic_core/medic_core.dart';

import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

/// The fields of the prescription form issued with Thông tư 18/2018/TT-BYT
/// (the template the project owner sent), filled from the visit and the
/// result. Drawn twice from the same data: as a widget for the preview and
/// as a PDF for printing, so what the doctor checks is what prints.
@immutable
class RxSheet {
  const RxSheet({
    required this.clinicName,
    required this.clinicPhone,
    required this.patientName,
    required this.age,
    required this.gender,
    required this.weightKg,
    required this.insuranceCode,
    required this.address,
    required this.diagnosis,
    required this.items,
    required this.advice,
    required this.date,
    required this.doctorName,
    this.claimCode,
  });

  final String clinicName, clinicPhone, patientName, gender, address;
  final int age;
  final num? weightKg;

  /// Empty when the person has no card or only a masked number is known;
  /// the form then shows a dotted line to fill by hand.
  final String insuranceCode;
  final String diagnosis;
  final List<PrescriptionItem> items;

  /// "Lời dặn" lines, the follow-up date last.
  final List<String> advice;
  final DateTime date;
  final String doctorName;

  /// Printed under the form once sent, for the patient to enter in the app.
  final String? claimCode;

  factory RxSheet.of({
    required ChartData chart,
    required StaffSession session,
    required List<(String, String)> diagnosis,
    required List<PrescriptionItem> items,
    required String advice,
    required String? followUpDate,
    DateTime? signedAt,
    String? signedBy,
    String? claimCode,
  }) {
    final p = chart.patient;
    return RxSheet(
      clinicName: session.clinic.name,
      clinicPhone: session.clinic.phone,
      patientName: p.brief.name,
      age: p.brief.age,
      gender: p.brief.gender,
      weightKg: p.weightKg,
      insuranceCode: p.insuranceCode.contains('•') ? '' : p.insuranceCode,
      address: p.address,
      diagnosis: diagnosis.map((d) => '${d.$2} (${d.$1})').join('; '),
      items: items,
      advice: [
        ...advice.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty),
        if (followUpDate != null) 'Hẹn tái khám ngày ${fmtDate(followUpDate)}.',
      ],
      date: signedAt ?? chart.now,
      doctorName: (signedBy ?? session.staff.name).replaceFirst('BS. ', ''),
      claimCode: claimCode,
    );
  }

  String get dateLine =>
      'Ngày ${date.day.toString().padLeft(2, '0')} tháng '
      '${date.month.toString().padLeft(2, '0')} năm ${date.year}';

  /// "Ngày uống 1 lần, mỗi lần 1 viên, sáng, sau ăn. Uống nhiều nước."
  static String usage(PrescriptionItem item) =>
      [item.usageLine, if (item.note.isNotEmpty) item.note].join('. ');
}

/// Paper look for the on-screen preview: white, black, serif, A4 ratio.
class RxSheetView extends StatelessWidget {
  const RxSheetView(this.sheet, {super.key});
  final RxSheet sheet;

  static const _ink = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontFamily: 'Tinos',
      fontSize: 15,
      height: 1.45,
      color: _ink,
    );
    const b = TextStyle(fontWeight: FontWeight.w700);
    Widget dots([double w = 160]) => Container(
      width: w,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _ink, width: 0.6)),
      ),
      height: 12,
    );
    Widget line(String label, Object? value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text('$label: '),
          if (value is String && value.isNotEmpty)
            Text(value, style: bold ? b : null)
          else
            dots(),
        ],
      ),
    );

    return Semantics(
      label: 'Đơn thuốc theo mẫu',
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 36),
        child: DefaultTextStyle(
          style: base,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line('Tên đơn vị', sheet.clinicName, bold: true),
              line('Điện thoại', sheet.clinicPhone),
              const SizedBox(height: 10),
              const Text(
                'ĐƠN THUỐC',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Họ tên: '),
                        TextSpan(
                          text: sheet.patientName.toUpperCase(),
                          style: b,
                        ),
                      ],
                    ),
                  ),
                  Text('Tuổi: ${sheet.age}'),
                  if (sheet.weightKg != null)
                    Text('Cân nặng: ${sheet.weightKg} kg')
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [const Text('Cân nặng: '), dots(50)],
                    ),
                  Text('Nam/nữ: ${sheet.gender}'),
                ],
              ),
              const SizedBox(height: 4),
              line('Mã số thẻ bảo hiểm y tế (nếu có)', sheet.insuranceCode),
              line('Địa chỉ liên hệ', sheet.address),
              line('Chẩn đoán', sheet.diagnosis, bold: true),
              const SizedBox(height: 6),
              const Text('Thuốc điều trị:', style: b),
              const SizedBox(height: 4),
              if (sheet.items.isEmpty)
                const Text(
                  'Không kê thuốc.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                )
              else
                for (final (i, item) in sheet.items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 24, child: Text('${i + 1}.')),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(item.title, style: b)),
                                  Text('${item.quantity} ${item.form}'),
                                ],
                              ),
                              Text(RxSheet.usage(item)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 6),
              const Text('Lời dặn:', style: b),
              if (sheet.advice.isEmpty)
                dots(double.infinity)
              else
                for (final a in sheet.advice) Text('- $a'),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      Text(
                        sheet.dateLine,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      const Text('Bác sỹ/Y sỹ khám bệnh'),
                      const Text(
                        '(Ký, ghi rõ họ tên)',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 56),
                      Text(sheet.doctorName, style: b),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '- Khám lại xin mang theo đơn này.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              if (sheet.claimCode != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Mã nhận kết quả trên MedicApp: ${sheet.claimCode}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Copies [text] and confirms with a snack bar.
Future<void> copyText(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }
}
