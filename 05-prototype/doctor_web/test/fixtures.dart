import 'dart:convert';

import 'package:doctor_web/data/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Sample answers shaped like `backend/CLINIC-API.md`, for bà Lan (shared,
/// with summary and 30 days of doses), anh Hòa (declined) and ông Minh
/// (result sent).
const today = '2026-11-19';
const historyDay = '2026-10-20';

String _day(int i) => DateTime.utc(
  2026,
  10,
  20,
).add(Duration(days: i)).toIso8601String().substring(0, 10);

const _atorvaSkips = {
  3: 'forgot',
  7: 'forgot',
  9: 'other',
  11: 'forgot',
  13: 'forgot',
  16: 'unwell',
  18: 'unwell',
  19: 'forgot',
  21: 'unwell',
  22: 'unwell',
  24: 'forgot',
  26: 'unwell',
};
const _alloSkips = {9: 'forgot', 20: 'forgot', 27: 'forgot'};

final _courses = [
  {
    'id': 'h-p2#1',
    'visitId': 'h-p2',
    'prescribedAt': '${historyDay}T06:30:00+07:00',
    'item': {
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
      'note': 'Uống nhiều nước trong ngày',
    },
  },
  {
    'id': 'h-p2#2',
    'visitId': 'h-p2',
    'prescribedAt': '${historyDay}T06:30:00+07:00',
    'item': {
      'name': 'Atorvastatin',
      'strength': '10mg',
      'form': 'viên',
      'quantity': 30,
      'route': 'Uống',
      'doses': [
        {'slot': 'evening', 'amount': 1},
      ],
      'meal': 'any',
      'days': 30,
      'note': '',
    },
  },
];

List<Map<String, Object?>> _log(
  String course,
  String slot,
  Map<int, String> skips,
) => [
  for (var i = 0; i < 30; i++)
    {
      'courseId': course,
      'day': _day(i),
      'slot': slot,
      'mark': skips.containsKey(i) ? 'skipped' : 'taken',
      'at': '${_day(i)}T${slot == 'morning' ? '07' : '19'}:20:00',
      'reason': skips[i],
    },
];

final doseLog = [
  ..._log('h-p2#1', 'morning', _alloSkips),
  ..._log('h-p2#2', 'evening', _atorvaSkips),
];

final _lastVisit = {
  'appointmentId': 'h-p2',
  'date': historyDay,
  'clinicName': 'Phòng khám Đa khoa An Bình',
  'doctorName': 'BS. Nguyễn Thu Hà',
  'diagnosis': [
    ['M10', 'Gút'],
    ['E78', 'Rối loạn lipid máu'],
  ],
  'items': [for (final c in _courses) c['item']],
  'advice': 'Uống đủ 2 lít nước mỗi ngày.',
  'followUpDate': today,
  'version': 1,
};

final worklist = {
  'date': today,
  'now': '${today}T08:40:00+07:00',
  'items': [
    {
      'appointmentId': 'a-p1',
      'time': '08:00',
      'status': 'done',
      'kind': 'Khám BHYT',
      'specialty': 'Nội tổng hợp',
      'patient': {
        'id': 'p1',
        'code': '000317',
        'name': 'Trần Văn Minh',
        'age': 52,
        'gender': 'Nam',
      },
      'consent': 'shared',
      'hasSummary': true,
      'flagged': false,
      'resultStatus': 'sent',
      'chiefComplaint': 'Tái khám tăng huyết áp.',
      'courses': <Object?>[],
      'doseLog': <Object?>[],
    },
    {
      'appointmentId': 'a-p2',
      'time': '08:30',
      'status': 'arrived',
      'kind': 'Khám dịch vụ',
      'specialty': 'Nội tổng hợp',
      'patient': {
        'id': 'p2',
        'code': '000482',
        'name': 'Phạm Thị Lan',
        'age': 78,
        'gender': 'Nữ',
      },
      'consent': 'shared',
      'hasSummary': true,
      'flagged': false,
      'resultStatus': 'none',
      'chiefComplaint': 'Đau khớp gối phải khoảng 1 tuần, sưng về đêm.',
      'courses': _courses,
      'doseLog': doseLog,
    },
    {
      'appointmentId': 'a-p3',
      'time': '09:00',
      'status': 'booked',
      'kind': 'Khám dịch vụ',
      'specialty': 'Nội tổng hợp',
      'patient': {
        'id': 'p3',
        'code': '000455',
        'name': 'Phạm Văn Hòa',
        'age': 49,
        'gender': 'Nam',
      },
      'consent': 'declined',
      'hasSummary': false,
      'flagged': false,
      'resultStatus': 'none',
      'chiefComplaint': null,
    },
  ],
};

final chartLan = {
  'appointment': {
    'id': 'a-p2',
    'time': '08:30',
    'startsAt': '${today}T08:30:00+07:00',
    'status': 'arrived',
    'kind': 'Khám dịch vụ',
    'specialty': 'Nội tổng hợp',
    'resultStatus': 'none',
  },
  'patient': {
    'id': 'p2',
    'code': '000482',
    'name': 'Phạm Thị Lan',
    'age': 78,
    'gender': 'Nữ',
    'birthDate': '1948-03-02',
    'address': 'Số 8 ngõ 25 phố Hoa Sữa, phường An Phú',
    'weightKg': 52,
    'insuranceCode': '',
    'allergy': 'Không ghi nhận',
    'conditions': ['Gút (M10)', 'Rối loạn lipid máu (E78)'],
  },
  'consent': {
    'state': 'shared',
    'grantedAt': '${today}T07:42:00+07:00',
    'expiresAt': '2026-12-19T07:42:00+07:00',
    'scope': ['intake', 'dose_log', 'self_meds'],
  },
  'period': {'from': historyDay, 'days': 30, 'now': '${today}T08:40:00+07:00'},
  'summary': {
    'id': 's-p2',
    'mode': 'mock',
    'createdAt': '2026-11-18T21:00:00+07:00',
    'sections': [
      {
        'key': 'chief',
        'text': 'Đau khớp gối phải khoảng 1 tuần, sưng về đêm.',
        'sources': ['i-1'],
      },
      {
        'key': 'course',
        'text': 'Đau tăng trong 2 ngày gần đây.',
        'sources': ['i-2'],
      },
      {
        'key': 'questions',
        'text': 'Có phải uống thuốc mỡ máu suốt đời không?',
        'sources': ['i-3'],
      },
    ],
    'flags': <Object?>[],
    'feedback': null,
  },
  'intake': [
    {
      'id': 'i-1',
      'channel': 'booking',
      'question': '',
      'answer': 'Dạo này cái gối bên phải đau quá, tối nằm thấy sưng lên.',
      'answeredAt': '2026-11-17T20:00:00+07:00',
    },
    {
      'id': 'i-2',
      'channel': 'pre_visit',
      'question': 'Nặng hơn hay nhẹ hơn?',
      'answer': 'Hai hôm nay đau hơn.',
      'answeredAt': '2026-11-18T20:00:00+07:00',
    },
    {
      'id': 'i-3',
      'channel': 'pre_visit',
      'question': 'Muốn hỏi bác sĩ điều gì?',
      'answer': 'Thuốc mỡ máu có phải uống mãi không.',
      'answeredAt': '2026-11-18T20:01:00+07:00',
    },
  ],
  'courses': _courses,
  'doseLog': doseLog,
  'selfMeds': [
    {'name': 'Paracetamol 500mg', 'how': '1 viên khi đau'},
  ],
  'lastVisit': _lastVisit,
};

final chartHoa = {
  'appointment': {
    'id': 'a-p3',
    'time': '09:00',
    'startsAt': '${today}T09:00:00+07:00',
    'status': 'booked',
    'kind': 'Khám dịch vụ',
    'specialty': 'Nội tổng hợp',
    'resultStatus': 'none',
  },
  'patient': {
    'id': 'p3',
    'code': '000455',
    'name': 'Phạm Văn Hòa',
    'age': 49,
    'gender': 'Nam',
    'birthDate': '1977-01-01',
    'conditions': <Object?>[],
  },
  'consent': {'state': 'declined'},
  'period': {'from': historyDay, 'days': 30, 'now': '${today}T08:40:00+07:00'},
  'summary': null,
  'intake': <Object?>[],
  'courses': <Object?>[],
  'doseLog': <Object?>[],
  'selfMeds': <Object?>[],
  'lastVisit': null,
};

const catalog = {
  'drugs': [
    {
      'name': 'Allopurinol',
      'strength': '300mg',
      'form': 'viên',
      'route': 'Uống',
    },
    {'name': 'Colchicin', 'strength': '1mg', 'form': 'viên', 'route': 'Uống'},
  ],
  'icd10': [
    ['M10', 'Gút'],
    ['M17', 'Thoái hóa khớp gối'],
  ],
};

const session = {
  'staff': {'id': 'd1', 'name': 'BS. Nguyễn Thu Hà', 'role': 'doctor'},
  'clinic': {
    'id': 'c1',
    'name': 'Phòng khám Đa khoa An Bình',
    'phone': '0900 000 000',
  },
};

/// A fake backend. [signedIn] starts the session; [calls] records requests.
class FakeBackend {
  FakeBackend({this.signedIn = true});
  bool signedIn;
  final calls = <String>[];

  /// Overrides anh Hòa's consent in his chart.
  Map<String, Object?>? hoaConsent;

  /// Bà Lan's result as the server holds it; null before the first draft.
  Map<String, Object?>? result;

  Map<String, Object?> _resultFrom(Map<String, Object?> body) => {
    'id': 'r-p2-${result?['version'] ?? 1}',
    'appointmentId': 'a-p2',
    'version': result?['version'] ?? 1,
    'status': 'draft',
    'amendReason': result?['amendReason'],
    'signedBy': null,
    'signedAt': null,
    'updatedAt': '${today}T08:45:00+07:00',
    'claimCode': result?['claimCode'],
    ...body,
  };

  http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  late final client = MockClient((req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (key == 'POST /v1/staff/login') {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      if (body['password'] != 'medicapp-demo') {
        return _json({
          'error': {
            'code': 'bad_credentials',
            'message': 'Email hoặc mật khẩu không đúng.',
          },
        }, 401);
      }
      signedIn = true;
      return _json(session);
    }
    if (!signedIn) {
      return _json({
        'error': {
          'code': 'unauthenticated',
          'message': 'Phiên đăng nhập đã hết.',
        },
      }, 401);
    }
    if (key == 'PUT /v1/appointments/a-p2/result-draft') {
      result = _resultFrom(jsonDecode(req.body) as Map<String, Object?>);
      return _json(result!);
    }
    if (key == 'POST /v1/appointments/a-p2/result/send') {
      result = {
        ...result!,
        'status': 'sent',
        'signedBy': 'BS. Nguyễn Thu Hà',
        'signedAt': '${today}T08:50:00+07:00',
        'claimCode': 'K7MQ-4XR2-9D',
      };
      return _json(result!);
    }
    if (key == 'POST /v1/appointments/a-p2/result/amend') {
      final reason = (jsonDecode(req.body) as Map)['reason'];
      result = {
        ...result!,
        'id': 'r-p2-2',
        'version': 2,
        'status': 'draft',
        'amendReason': reason,
      };
      return _json(result!, 201);
    }
    return switch (key) {
      'GET /v1/clinic/catalog' => _json(catalog),
      'GET /v1/appointments/a-p2/result' => _json(result),

      'GET /v1/staff/me' => _json(session),
      'POST /v1/staff/logout' => http.Response('', 204),
      'GET /v1/clinic/worklist' => _json(worklist),
      'GET /v1/appointments/a-p2/chart' => _json(chartLan),
      'GET /v1/appointments/a-p3/chart' => _json({
        ...chartHoa,
        'consent': hoaConsent ?? chartHoa['consent'],
      }),
      'GET /v1/patients/p2/history' => _json([_lastVisit]),
      'POST /v1/summaries/s-p2/feedback' => _json({
        'feedback': {'value': 'up'},
      }),
      _ => _json({
        'error': {'code': 'not_found', 'message': 'Không tìm thấy.'},
      }, 404),
    };
  });

  ClinicApi get api => ClinicApi(client, baseUrl: 'http://test');
}
