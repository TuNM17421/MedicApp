import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/features/records/data/doctor_portal.dart';
import 'package:medic_app/features/records/domain/claim_code.dart';

import '../visit_prep/visit_prep_test.dart' show visit;

/// What `GET /v1/results/claim/:code` returns (CLINIC-API.md): a
/// VisitResult without visitId and profileId.
Map<String, Object?> _claimBody() => {
  'appointmentId': 'apt_1',
  'version': 2,
  'issuedAt': '2026-10-14T09:12:00.000',
  'facilityName': 'Phòng khám Đa khoa Minh An',
  'facilityPhone': '02838123456',
  'doctorName': 'BS. Lê Thu Hà',
  'patientName': 'Trần Văn Minh',
  'patientAge': 67,
  'patientGender': 'Nam',
  'address': 'Q.3, TP.HCM',
  'insuranceCode': 'HT••••••••456',
  'weightKg': null,
  'diagnosis': 'Gút (M10); Rối loạn lipid máu (E78)',
  'items': [
    {
      'name': 'Allopurinol',
      'strength': '300mg',
      'form': 'viên',
      'quantity': 30,
      'route': 'Uống',
      'doses': [
        {'slot': 'morning', 'amount': 1},
      ],
      'meal': 'after',
      'days': 30,
      'note': '',
    },
  ],
  'advice': ['Uống đủ 2 lít nước mỗi ngày.', 'Hẹn tái khám ngày 13/11/2026.'],
  'followUpDate': '2026-11-13T00:00:00.000',
};

http.Response _error(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': 'server text'},
  }),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  group('claim code', () {
    test('normalises like the backend (Crockford)', () {
      expect(normalizeClaimCode('K7MQ-4XR2-9D'), 'K7MQ4XR29D');
      expect(normalizeClaimCode(' k7mq 4xr2 9d '), 'K7MQ4XR29D');
      expect(normalizeClaimCode('oiLO-1234-AB'), '01101234AB');
      expect(normalizeClaimCode('K7MQ-4XR2-9'), isNull, reason: 'too short');
      expect(normalizeClaimCode('K7MQ-4XR2-9DD'), isNull, reason: 'too long');
      expect(normalizeClaimCode('K7MQ-4XR2-9U'), isNull, reason: 'U unused');
      expect(normalizeClaimCode('K7MQ.4XR2.9D'), isNull);
    });

    test('formats as XXXX-XXXX-XX', () {
      expect(formatClaimCode(''), '');
      expect(formatClaimCode('K7M'), 'K7M');
      expect(formatClaimCode('K7MQ'), 'K7MQ');
      expect(formatClaimCode('K7MQ4'), 'K7MQ-4');
      expect(formatClaimCode('K7MQ4XR29D'), 'K7MQ-4XR2-9D');
    });

    test('input formatter upper-cases, groups and caps at 10', () {
      const formatter = ClaimCodeInputFormatter();
      TextEditingValue type(String text) => formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      expect(type('k7mq4').text, 'K7MQ-4');
      expect(type('k7mq4').selection.baseOffset, 6);
      expect(type('k7mq 4xr2 9d').text, 'K7MQ-4XR2-9D');
      expect(type('k7mq4xr29dzz').text, 'K7MQ-4XR2-9D');
      expect(type('olo').text, '010');
    });
  });

  group('HttpDoctorPortal.claim', () {
    final appointment = visit(id: 'V7', patientId: 'mother');

    test('200 attaches the result to the app visit', () async {
      late Uri asked;
      final portal = HttpDoctorPortal(
        baseUrl: 'http://clinic.test',
        client: MockClient((request) async {
          asked = request.url;
          return http.Response.bytes(
            utf8.encode(jsonEncode(_claimBody())),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      final result = await portal.claim('k7mq-4xr2-9o', visit: appointment);
      expect(
        asked.toString(),
        'http://clinic.test/v1/results/claim/K7MQ4XR290',
      );
      expect(result.visitId, 'V7');
      expect(result.profileId, 'mother');
      expect(result.patientName, 'Trần Văn Minh');
      expect(result.items.single.title, 'Allopurinol 300mg');
      expect(result.followUpDate, DateTime(2026, 11, 13));
    });

    Future<ResultClaimException> failure(MockClient client, [String? code]) {
      final portal = HttpDoctorPortal(
        baseUrl: 'http://clinic.test',
        client: client,
      );
      return portal
          .claim(code ?? 'K7MQ-4XR2-9D', visit: appointment)
          .then<ResultClaimException>(
            (_) => fail('expected a ResultClaimException'),
            onError: (Object error) => error as ResultClaimException,
          );
    }

    test('404 says the code is wrong or expired', () async {
      final error = await failure(
        MockClient((_) async => _error(404, 'not_found')),
      );
      expect(error.message, 'Mã không đúng hoặc đã hết hạn.');
    });

    test('429 asks to wait a minute', () async {
      final error = await failure(
        MockClient((_) async => _error(429, 'rate_limited')),
      );
      expect(error.message, 'Bạn nhập sai nhiều lần. Thử lại sau 1 phút.');
    });

    test('network failure has its own message', () async {
      final error = await failure(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(error, ResultClaimException.network);
    });

    test('a malformed code never reaches the server', () async {
      var calls = 0;
      final error = await failure(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
        'K7MQ-4XR',
      );
      expect(error, ResultClaimException.invalid);
      expect(calls, 0);
    });

    test('an unexpected body is a server error, not a crash', () async {
      final error = await failure(
        MockClient((_) async => http.Response('{"diagnosis": 1}', 200)),
      );
      expect(error, ResultClaimException.server);
    });
  });

  test('mock portal accepts any well-formed code', () async {
    const portal = MockDoctorPortal(latency: Duration.zero);
    final result = await portal.claim(
      'aaaa-bbbb-cc',
      visit: visit(id: 'V9', patientId: 'mother'),
      patient: demoProfiles[1],
    );
    expect(result.visitId, 'V9');
    await expectLater(
      portal.claim('abc', visit: visit(id: 'V9')),
      throwsA(ResultClaimException.invalid),
    );
  });
}
