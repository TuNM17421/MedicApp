import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:medic_core/medic_core.dart';

import '../domain/sharing_models.dart';

/// Why a call to the patient API failed. [message] is ready to show;
/// [code] is the backend's error code, or `network` / `server`.
class PatientApiException implements Exception {
  const PatientApiException(this.code, this.message, {this.status});
  final String code, message;

  /// HTTP status, null when the server was not reached.
  final int? status;

  static const network = PatientApiException(
    'network',
    'Chưa kết nối được phòng khám. Kiểm tra mạng rồi thử lại.',
  );
  static const server = PatientApiException(
    'server',
    'Phòng khám chưa trả lời được. Bạn thử lại sau ít phút nhé.',
  );

  /// Not worth sending again as is: the server understood and said no
  /// (validation, missing consent, unknown or cancelled appointment).
  bool get permanent =>
      status != null &&
      status! >= 400 &&
      status! < 500 &&
      status != 401 &&
      status != 408 &&
      status != 429;

  @override
  String toString() => 'PatientApiException($code, $status)';
}

const _messages = {
  'bad_phone': 'Số điện thoại gồm 10 chữ số, bắt đầu bằng số 0.',
  'bad_code':
      'Mã chưa đúng hoặc đã hết hạn. Bạn kiểm tra lại, hoặc bấm '
      '"Gửi lại mã".',
  'rate_limited': 'Bạn đã thử nhiều lần. Vui lòng đợi ít phút rồi thử lại.',
  'otp_unavailable':
      'Phòng khám tạm thời chưa gửi được mã. Bạn thử lại sau nhé.',
  'unauthenticated': 'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại.',
  'consent_required': 'Bạn chưa đồng ý chia sẻ mục này với phòng khám.',
  'bad_state': 'Lịch hẹn này đã hủy nên không chia sẻ được.',
  'not_found': 'Không tìm thấy lịch hẹn này ở phòng khám.',
};

/// Answer to `POST /v1/patient/otp`.
class OtpChallenge {
  const OtpChallenge({required this.expiresIn, this.devCode});
  final int expiresIn;

  /// Only from a development server (`PATIENT_OTP_MODE=dev`), so demos work
  /// without SMS. Shown as "Mã thử: 123456".
  final String? devCode;
}

class DoseUploadResult {
  const DoseUploadResult({required this.accepted, this.ignored = const []});
  final int accepted;

  /// Course ids the server did not take (unknown course or no consent).
  final List<String> ignored;
}

/// The patient side of the clinic backend (bước 16, step16-contract.md).
abstract class PatientApi {
  Future<OtpChallenge> requestOtp(String phone);
  Future<PatientSession> createSession(String phone, String code);
  Future<void> deleteSession(String token);
  Future<List<ServerAppointment>> appointments(
    String token, {
    String fallbackName = '',
  });

  /// The latest sent result, attached to [appointmentId] as visit id so the
  /// medication course ids match the server's (`<appointmentId>#<n>`).
  /// Null when the clinic has not sent one.
  Future<VisitResult?> result(
    String token,
    String appointmentId, {
    required String profileId,
  });
  Future<SharingConsent> grantConsent(
    String token,
    String appointmentId,
    Set<ShareScope> scope,
  );
  Future<SharingConsent> revokeConsent(String token, String appointmentId);
  Future<int> putIntake(
    String token,
    String appointmentId,
    List<Map<String, Object?>> answers,
  );
  Future<int> putSelfMeds(
    String token,
    String appointmentId,
    List<Map<String, Object?>> items,
  );
  Future<DoseUploadResult> postDoseEvents(
    String token,
    List<Map<String, Object?>> events,
  );
}

class HttpPatientApi implements PatientApi {
  HttpPatientApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<Object?> _send(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on Exception {
      throw PatientApiException.network;
    }
    final status = response.statusCode;
    Object? decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
    }
    if (status >= 200 && status < 300) return decoded;
    final code = switch (decoded) {
      {'error': {'code': final String code}} => code,
      _ => switch (status) {
        401 => 'unauthenticated',
        404 => 'not_found',
        429 => 'rate_limited',
        _ => 'server',
      },
    };
    throw PatientApiException(
      code,
      _messages[code] ?? PatientApiException.server.message,
      status: status,
    );
  }

  /// Reads a 2xx body; a body of the wrong shape is a server error.
  T _read<T>(Object? body, T Function(Map<String, Object?>) parse) {
    try {
      return parse((body! as Map).cast<String, Object?>());
    } on Object {
      throw PatientApiException.server;
    }
  }

  @override
  Future<OtpChallenge> requestOtp(String phone) async {
    final body = await _send('POST', '/v1/patient/otp', body: {'phone': phone});
    return _read(
      body,
      (json) => OtpChallenge(
        expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 300,
        devCode: json['devCode'] as String?,
      ),
    );
  }

  @override
  Future<PatientSession> createSession(String phone, String code) async {
    final body = await _send(
      'POST',
      '/v1/patient/session',
      body: {'phone': phone, 'code': code},
    );
    return _read(body, (json) {
      final patient = (json['patient'] as Map?)?.cast<String, Object?>();
      return PatientSession(
        token: json['token']! as String,
        expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
        phone: patient?['phone'] as String? ?? phone,
        name: patient?['name'] as String? ?? '',
      );
    });
  }

  @override
  Future<void> deleteSession(String token) =>
      _send('DELETE', '/v1/patient/session', token: token);

  @override
  Future<List<ServerAppointment>> appointments(
    String token, {
    String fallbackName = '',
  }) async {
    final body = await _send('GET', '/v1/patient/appointments', token: token);
    try {
      return List.unmodifiable([
        for (final item in body! as List<Object?>)
          ServerAppointment.fromJson(
            (item! as Map).cast<String, Object?>(),
            fallbackName: fallbackName,
          ),
      ]);
    } on Object {
      throw PatientApiException.server;
    }
  }

  @override
  Future<VisitResult?> result(
    String token,
    String appointmentId, {
    required String profileId,
  }) async {
    final Object? body;
    try {
      body = await _send(
        'GET',
        '/v1/patient/appointments/${Uri.encodeComponent(appointmentId)}/result',
        token: token,
      );
    } on PatientApiException catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
    return _read(
      body,
      (json) => VisitResult.fromJson({
        ...json,
        'issuedAt': _clock(json['issuedAt']),
        'followUpDate': _clock(json['followUpDate']),
        'visitId': appointmentId,
        'profileId': profileId,
      }),
    );
  }

  String _appointment(String id) =>
      '/v1/patient/appointments/${Uri.encodeComponent(id)}';

  @override
  Future<SharingConsent> grantConsent(
    String token,
    String appointmentId,
    Set<ShareScope> scope,
  ) async {
    final body = await _send(
      'PUT',
      '${_appointment(appointmentId)}/consent',
      token: token,
      body: {
        'scope': [
          for (final value in ShareScope.values)
            if (scope.contains(value)) value.wire,
        ],
        'wordingVersion': sharingWordingVersion,
      },
    );
    return _read(body, SharingConsent.fromJson);
  }

  @override
  Future<SharingConsent> revokeConsent(
    String token,
    String appointmentId,
  ) async {
    final body = await _send(
      'DELETE',
      '${_appointment(appointmentId)}/consent',
      token: token,
    );
    return _read(body, SharingConsent.fromJson);
  }

  @override
  Future<int> putIntake(
    String token,
    String appointmentId,
    List<Map<String, Object?>> answers,
  ) async {
    final body = await _send(
      'PUT',
      '${_appointment(appointmentId)}/intake',
      token: token,
      body: {'answers': answers},
    );
    return _read(body, (json) => (json['count']! as num).toInt());
  }

  @override
  Future<int> putSelfMeds(
    String token,
    String appointmentId,
    List<Map<String, Object?>> items,
  ) async {
    final body = await _send(
      'PUT',
      '${_appointment(appointmentId)}/self-meds',
      token: token,
      body: {'items': items},
    );
    return _read(body, (json) => (json['count']! as num).toInt());
  }

  @override
  Future<DoseUploadResult> postDoseEvents(
    String token,
    List<Map<String, Object?>> events,
  ) async {
    final body = await _send(
      'POST',
      '/v1/patient/dose-events',
      token: token,
      body: {'events': events},
    );
    return _read(
      body,
      (json) => DoseUploadResult(
        accepted: (json['accepted']! as num).toInt(),
        ignored: [
          for (final id in json['ignored'] as List<Object?>? ?? const [])
            id! as String,
        ],
      ),
    );
  }
}

/// Times with an offset become naive Vietnam wall-clock values, as the
/// medication schedule in `medic_core` expects; dates without one are kept.
Object? _clock(Object? value) {
  if (value is! String) return value;
  final parsed = DateTime.parse(value);
  return parsed.isUtc ? vietnamClock(parsed).toIso8601String() : value;
}

/// A dose mark as the clinic stores it (`POST /v1/patient/dose-events`).
Map<String, Object?> doseEventWire(DoseLogEntry entry) => {
  'courseId': entry.courseId,
  'day': entry.day,
  'slot': entry.slot.name,
  'mark': entry.mark.name,
  'reason': entry.reason?.name,
  'at': vietnamIso(entry.at),
};
