import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'rx_sheet.dart';

/// Tinos is metric-compatible with Times New Roman (the font of the
/// ministry's template), has every Vietnamese letter, and may be embedded
/// (SIL OFL); Times New Roman itself may not.
Future<pw.ThemeData> _theme(Future<ByteData> Function(String) load) async {
  Future<pw.Font> font(String name) async =>
      pw.Font.ttf(await load('assets/fonts/tinos/Tinos-$name.ttf'));
  return pw.ThemeData.withFont(
    base: await font('Regular'),
    bold: await font('Bold'),
    italic: await font('Italic'),
    boldItalic: await font('BoldItalic'),
  );
}

/// The prescription as an A4 PDF, 14 pt, one page for a usual prescription.
Future<Uint8List> buildRxPdf(
  RxSheet s, {
  Future<ByteData> Function(String)? load,
}) async {
  final theme = await _theme(load ?? rootBundle.load);
  const size = 14.0;
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final italic = pw.TextStyle(fontStyle: pw.FontStyle.italic);
  pw.Widget dots([double w = 160]) => pw.Container(
    width: w,
    height: 10,
    margin: const pw.EdgeInsets.only(bottom: 3),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(width: 0.5, style: pw.BorderStyle.dotted),
      ),
    ),
  );
  pw.Widget line(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: value.isEmpty
            ? pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('$label: '),
                  pw.Expanded(child: dots()),
                ],
              )
            : pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(text: '$label: '),
                    pw.TextSpan(text: value, style: strong ? bold : null),
                  ],
                ),
              ),
      );

  final doc = pw.Document(
    title: 'Đơn thuốc ${s.patientName}',
    author: s.clinicName,
    theme: theme.copyWith(
      defaultTextStyle: pw.TextStyle(fontSize: size, lineSpacing: 2),
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginTop: 20 * PdfPageFormat.mm,
        marginBottom: 20 * PdfPageFormat.mm,
        marginLeft: 18 * PdfPageFormat.mm,
        marginRight: 18 * PdfPageFormat.mm,
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          line('Tên đơn vị', s.clinicName, strong: true),
          line('Điện thoại', s.clinicPhone),
          pw.SizedBox(height: 8),
          pw.Text(
            'ĐƠN THUỐC',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 18,
            children: [
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    const pw.TextSpan(text: 'Họ tên: '),
                    pw.TextSpan(text: s.patientName.toUpperCase(), style: bold),
                  ],
                ),
              ),
              pw.Text('Tuổi: ${s.age}'),
              s.weightKg != null
                  ? pw.Text('Cân nặng: ${s.weightKg} kg')
                  : pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [pw.Text('Cân nặng: '), dots(40)],
                    ),
              pw.Text('Nam/nữ: ${s.gender}'),
            ],
          ),
          pw.SizedBox(height: 3),
          line('Mã số thẻ bảo hiểm y tế (nếu có)', s.insuranceCode),
          line('Địa chỉ liên hệ', s.address),
          line('Chẩn đoán', s.diagnosis, strong: true),
          pw.SizedBox(height: 4),
          pw.Text('Thuốc điều trị:', style: bold),
          pw.SizedBox(height: 3),
          if (s.items.isEmpty) pw.Text('Không kê thuốc.', style: italic),
          for (final (i, item) in s.items.indexed)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(width: 20, child: pw.Text('${i + 1}.')),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Text(item.title, style: bold),
                            ),
                            pw.Text('${item.quantity} ${item.form}'),
                          ],
                        ),
                        pw.Text(RxSheet.usage(item)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 4),
          pw.Text('Lời dặn:', style: bold),
          if (s.advice.isEmpty) dots(double.infinity),
          for (final a in s.advice) pw.Text('- $a'),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(
                children: [
                  pw.Text(s.dateLine, style: italic),
                  pw.Text('Bác sỹ/Y sỹ khám bệnh'),
                  pw.Text('(Ký, ghi rõ họ tên)', style: italic),
                  pw.SizedBox(height: 48),
                  pw.Text(s.doctorName, style: bold),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text('- Khám lại xin mang theo đơn này.', style: italic),
          if (s.claimCode != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Mã nhận kết quả trên MedicApp: ${s.claimCode}',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}

const _plain = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

/// "don-thuoc-tran-van-minh-2026-10-16.pdf": plain ASCII, since browsers
/// may drop a download name with Vietnamese letters.
String rxFileName(RxSheet s) {
  final name = s.patientName.toLowerCase().split('').map((ch) {
    for (final MapEntry(:key, :value) in _plain.entries) {
      if (value.contains(ch)) return key;
    }
    return ch;
  }).join();
  final slug = name.replaceAll(RegExp('[^a-z0-9]+'), '-');
  final d = s.date;
  return 'don-thuoc-$slug-${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}.pdf';
}

/// Opens the browser's print dialog with the PDF.
Future<void> printRx(RxSheet sheet) => Printing.layoutPdf(
  name: rxFileName(sheet),
  format: PdfPageFormat.a4,
  onLayout: (_) => buildRxPdf(sheet),
);

/// Saves the PDF (a download in the browser).
Future<void> downloadRx(RxSheet sheet) async => Printing.sharePdf(
  bytes: await buildRxPdf(sheet),
  filename: rxFileName(sheet),
);
