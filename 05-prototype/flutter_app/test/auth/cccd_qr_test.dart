import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/features/profiles/cccd_qr.dart';

import 'auth_fakes.dart';

void main() {
  final today = DateTime(2026, 10, 15);

  test('reads every field of the 7-field layout', () {
    final data = parseCccdQr(sampleCccdQr, today: today);
    expect(data.idNumber, '079065001234');
    expect(data.oldIdNumber, isNull);
    expect(data.name, 'Trần Thị Mai');
    expect(data.birthDate, DateTime(1965, 3, 15));
    expect(data.gender, 'Nữ');
    expect(data.address, startsWith('Số 12 Nguyễn Trãi'));
    expect(data.issueDate, DateTime(2021, 7, 1));
    expect(data.maskedIdNumber, '079••••••234');
  });

  test('accepts newer cards with extra empty fields and an old ID', () {
    final data = parseCccdQr(
      '001062009876|012345678|  Lê   Văn  Bình |02011962|Nam|Hà Nội|10052022||||',
      today: today,
    );
    expect(data.name, 'Lê Văn Bình');
    expect(data.oldIdNumber, '012345678');
    expect(data.gender, 'Nam');
    expect(data.issueDate, DateTime(2022, 5, 10));
  });

  test('rejects QR codes that are not a CCCD', () {
    for (final raw in [
      'https://example.com',
      '12345|a|b|c|d|e|f',
      '079065001234|Nguyễn Văn A',
    ]) {
      expect(
        () => parseCccdQr(raw, today: today),
        throwsA(
          isA<CccdQrException>().having(
            (e) => e.error,
            'error',
            CccdQrError.notCccd,
          ),
        ),
        reason: raw,
      );
    }
  });

  test('rejects a CCCD layout with no usable name or birth date', () {
    for (final raw in [
      '079065001234||Trần Thị Mai|31021965|Nữ|Hà Nội|01072021',
      '079065001234||Trần Thị Mai|01012030|Nữ|Hà Nội|01072021',
      '079065001234|||15031965|Nữ|Hà Nội|01072021',
    ]) {
      expect(
        () => parseCccdQr(raw, today: today),
        throwsA(
          isA<CccdQrException>().having(
            (e) => e.error,
            'error',
            CccdQrError.unreadable,
          ),
        ),
        reason: raw,
      );
    }
  });
}
