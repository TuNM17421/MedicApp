import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medic_app/features/sharing/data/patient_api.dart';
import 'package:medic_app/features/sharing/domain/sharing_models.dart';
import 'package:medic_core/medic_core.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _error(int status, String code) => _json({
  'error': {'code': code, 'message': 'server text'},
}, status);

const _consentView = {
  'state': 'shared',
  'scope': ['intake', 'dose_log'],
  'grantedAt': '2026-10-16T09:00:00+07:00',
  'expiresAt': '2026-11-15T08:30:00+07:00',
  'revokedAt': null,
};

/// One request as the fake server saw it.
typedef Seen = ({String method, String path, String? auth, Object? body});

(HttpPatientApi, List<Seen>) _api(
  http.Response Function(http.Request request) answer,
) {
  final seen = <Seen>[];
  final api = HttpPatientApi(
    baseUrl: 'http://clinic.test',
    client: MockClient((request) async {
      seen.add((
        method: request.method,
        path: request.url.path,
        auth: request.headers['authorization'],
        body: request.body.isEmpty ? null : jsonDecode(request.body),
      ));
      return answer(request);
    }),
  );
  return (api, seen);
}

Future<PatientApiException> _failure(Future<Object?> call) => call.then(
  (_) => fail('expected a PatientApiException'),
  onError: (Object error) => error as PatientApiException,
);

void main() {
  group('sign-in', () {
    test('OTP request returns the dev code', () async {
      final (api, seen) = _api(
        (_) => _json({'expiresIn': 300, 'devCode': '123456'}, 202),
      );
      final challenge = await api.requestOtp('0912000482');
      expect(challenge.expiresIn, 300);
      expect(challenge.devCode, '123456');
      expect(seen.single.method, 'POST');
      expect(seen.single.path, '/v1/patient/otp');
      expect(seen.single.body, {'phone': '0912000482'});
      expect(seen.single.auth, isNull);
    });

    test('production OTP has no dev code', () async {
      final (api, _) = _api((_) => _json({'expiresIn': 300}, 202));
      expect((await api.requestOtp('0912000482')).devCode, isNull);
    });

    test('session returns the token and patient', () async {
      final (api, seen) = _api(
        (_) => _json({
          'token': 'abc',
          'expiresAt': '2026-11-15T09:00:00+07:00',
          'patient': {'phone': '0912000482', 'name': 'Phạm Thị Lan'},
        }),
      );
      final session = await api.createSession('0912000482', '123456');
      expect(seen.single.path, '/v1/patient/session');
      expect(seen.single.body, {'phone': '0912000482', 'code': '123456'});
      expect(session.token, 'abc');
      expect(session.name, 'Phạm Thị Lan');
      expect(session.expiresAt, DateTime.utc(2026, 11, 15, 2));
    });

    test('error codes map to friendly messages', () async {
      for (final (status, code, message) in [
        (401, 'bad_code', 'Mã chưa đúng'),
        (422, 'bad_phone', 'Số điện thoại gồm 10 chữ số'),
        (429, 'rate_limited', 'đợi ít phút'),
        (503, 'otp_unavailable', 'chưa gửi được mã'),
      ]) {
        final (api, _) = _api((_) => _error(status, code));
        final error = await _failure(api.createSession('0912000482', '1'));
        expect(error.code, code);
        expect(error.status, status);
        expect(error.message, contains(message));
      }
    });

    test('sign-out sends the bearer token', () async {
      final (api, seen) = _api((_) => http.Response('', 204));
      await api.deleteSession('abc');
      expect(seen.single.method, 'DELETE');
      expect(seen.single.path, '/v1/patient/session');
      expect(seen.single.auth, 'Bearer abc');
    });

    test('network failure has its own message', () async {
      final api = HttpPatientApi(
        baseUrl: 'http://clinic.test',
        client: MockClient((_) => throw http.ClientException('offline')),
      );
      expect(
        await _failure(api.requestOtp('0912000482')),
        PatientApiException.network,
      );
    });
  });

  group('appointments and results', () {
    test('lists appointments with clinic and consent', () async {
      final (api, seen) = _api(
        (_) => _json([
          {
            'id': 'a-p2',
            'clinic': {
              'id': 'c-anbinh',
              'name': 'Phòng khám Đa khoa An Bình',
              'phone': '0900 000 000',
            },
            'startsAt': '2026-10-16T08:30:00+07:00',
            'time': '08:30',
            'specialty': 'Nội tổng hợp',
            'kind': 'Khám dịch vụ',
            'status': 'arrived',
            'resultStatus': 'draft',
            'consent': _consentView,
            'intakeCount': 3,
            'selfMeds': [
              {'name': 'Panadol', 'how': '1 viên khi đau'},
            ],
          },
        ]),
      );
      final list = await api.appointments('tok', fallbackName: 'Lan');
      expect(seen.single.auth, 'Bearer tok');
      expect(seen.single.path, '/v1/patient/appointments');
      final item = list.single;
      expect(item.clinic.name, 'Phòng khám Đa khoa An Bình');
      expect(item.start, DateTime(2026, 10, 16, 8, 30));
      expect(item.resultStatus, 'none', reason: 'a draft is not a result');
      expect(item.consent!.scope, {ShareScope.intake, ShareScope.doseLog});
      expect(item.consent!.activeAt(DateTime.utc(2026, 10, 20)), isTrue);
      expect(item.selfMeds.single.name, 'Panadol');
      expect(item.patientName, 'Lan');
      final restored = ServerAppointment.fromJson(item.toJson());
      expect(restored.consent!.expiresAt, item.consent!.expiresAt);
      expect(restored.start, item.start);
    });

    test('result uses the appointment as visit id', () async {
      final (api, seen) = _api(
        (_) => _json({
          'appointmentId': 'a-p1',
          'version': 1,
          'issuedAt': '2026-10-16T08:24:00+07:00',
          'facilityName': 'Phòng khám Đa khoa An Bình',
          'facilityPhone': '0900 000 000',
          'doctorName': 'BS. Nguyễn Thu Hà',
          'patientName': 'Trần Văn Minh',
          'patientAge': 52,
          'patientGender': 'Nam',
          'diagnosis': 'Tăng huyết áp (I10)',
          'items': [
            {
              'name': 'Amlodipin',
              'strength': '5mg',
              'form': 'viên',
              'quantity': 28,
              'doses': [
                {'slot': 'morning', 'amount': 1},
              ],
              'days': 28,
            },
          ],
          'advice': ['Ăn nhạt.'],
          'followUpDate': '2026-11-13',
        }),
      );
      final result = await api.result('tok', 'a-p1', profileId: 'self');
      expect(seen.single.path, '/v1/patient/appointments/a-p1/result');
      expect(result!.visitId, 'a-p1');
      expect(result.profileId, 'self');
      expect(result.issuedAt, DateTime(2026, 10, 16, 8, 24));
      expect(coursesFrom([result]).single.id, 'a-p1#1');
    });

    test('no result yet is null, not an error', () async {
      final (api, _) = _api((_) => _error(404, 'not_found'));
      expect(await api.result('tok', 'a-p1', profileId: 'self'), isNull);
    });

    test('expired token is unauthenticated', () async {
      final (api, _) = _api((_) => _error(401, 'unauthenticated'));
      final error = await _failure(api.appointments('old'));
      expect(error.code, 'unauthenticated');
      expect(error.permanent, isFalse);
    });

    test('a body of the wrong shape is a server error', () async {
      final (api, _) = _api((_) => _json({'items': 1}));
      expect(
        await _failure(api.appointments('tok')),
        PatientApiException.server,
      );
    });
  });

  group('consent', () {
    test('grant sends the scope and wording version', () async {
      final (api, seen) = _api((_) => _json(_consentView));
      final consent = await api.grantConsent('tok', 'a-p2', {
        ShareScope.doseLog,
        ShareScope.intake,
      });
      expect(seen.single.method, 'PUT');
      expect(seen.single.path, '/v1/patient/appointments/a-p2/consent');
      expect(seen.single.body, {
        'scope': ['intake', 'dose_log'],
        'wordingVersion': 2,
      });
      expect(consent.state, SharingState.shared);
    });

    test('withdraw returns the revoked view', () async {
      final (api, seen) = _api(
        (_) => _json({
          ..._consentView,
          'state': 'revoked',
          'revokedAt': '2026-10-16T10:00:00+07:00',
        }),
      );
      final consent = await api.revokeConsent('tok', 'a-p2');
      expect(seen.single.method, 'DELETE');
      expect(consent.state, SharingState.revoked);
      expect(consent.activeAt(DateTime.utc(2026, 10, 17)), isFalse);
    });

    test('cancelled appointment is refused for good', () async {
      final (api, _) = _api((_) => _error(409, 'bad_state'));
      final error = await _failure(
        api.grantConsent('tok', 'a-p2', {ShareScope.intake}),
      );
      expect(error.message, contains('đã hủy'));
      expect(error.permanent, isTrue);
    });
  });

  group('uploads', () {
    test('intake answers with stable ids and offset times', () async {
      final (api, seen) = _api((_) => _json({'count': 1}));
      final answer = IntakeAnswer(
        id: 'pre_visit.ask',
        channel: IntakeChannel.preVisit,
        question: 'Bạn muốn hỏi bác sĩ điều gì?',
        answer: 'Thuốc mỡ máu có phải uống mãi không?',
        answeredAt: DateTime(2026, 10, 15, 20, 5),
      );
      expect(await api.putIntake('tok', 'a-p2', [answer.toWire()]), 1);
      expect(seen.single.method, 'PUT');
      expect(seen.single.path, '/v1/patient/appointments/a-p2/intake');
      expect(seen.single.body, {
        'answers': [
          {
            'id': 'pre_visit.ask',
            'channel': 'pre_visit',
            'question': 'Bạn muốn hỏi bác sĩ điều gì?',
            'answer': 'Thuốc mỡ máu có phải uống mãi không?',
            'answeredAt': '2026-10-15T20:05:00+07:00',
          },
        ],
      });
    });

    test('self meds replace the list', () async {
      final (api, seen) = _api((_) => _json({'count': 1}));
      await api.putSelfMeds('tok', 'a-p2', [
        const SelfMed(name: 'Panadol', how: 'Khi đau').toJson(),
      ]);
      expect(seen.single.path, '/v1/patient/appointments/a-p2/self-meds');
      expect(seen.single.body, {
        'items': [
          {'name': 'Panadol', 'how': 'Khi đau'},
        ],
      });
    });

    test('dose events report ignored courses', () async {
      final (api, seen) = _api(
        (_) => _json({
          'accepted': 1,
          'ignored': ['other#1'],
        }),
      );
      final event = doseEventWire(
        DoseLogEntry(
          courseId: 'a-p1#1',
          day: '2026-10-16',
          slot: DoseSlot.morning,
          mark: DoseMark.skipped,
          at: DateTime(2026, 10, 16, 7, 40),
          reason: SkipReason.forgot,
        ),
      );
      final result = await api.postDoseEvents('tok', [event]);
      expect(seen.single.path, '/v1/patient/dose-events');
      expect(seen.single.body, {
        'events': [
          {
            'courseId': 'a-p1#1',
            'day': '2026-10-16',
            'slot': 'morning',
            'mark': 'skipped',
            'reason': 'forgot',
            'at': '2026-10-16T07:40:00+07:00',
          },
        ],
      });
      expect(result.accepted, 1);
      expect(result.ignored, ['other#1']);
    });

    test('403 consent_required is a permanent refusal', () async {
      final (api, _) = _api((_) => _error(403, 'consent_required'));
      final error = await _failure(api.postDoseEvents('tok', const []));
      expect(error.code, 'consent_required');
      expect(error.permanent, isTrue);
    });

    test('server errors and rate limits are worth retrying', () async {
      for (final (status, code) in [
        (500, 'server'),
        (503, 'clinic_unavailable'),
        (429, 'rate_limited'),
      ]) {
        final (api, _) = _api((_) => _error(status, code));
        final error = await _failure(api.putIntake('tok', 'a-p2', const []));
        expect(error.permanent, isFalse, reason: code);
      }
    });
  });
}
