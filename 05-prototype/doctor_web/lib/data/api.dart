import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'result.dart';

/// Base URL of the backend. Empty means the page's own origin, which is how
/// the backend serves the built web at `/doctor/`. For `flutter run`, pass
/// `--dart-define=API_BASE_URL=http://localhost:8080`.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);
  final int status;
  final String code, message;

  bool get unauthenticated => status == 401;

  @override
  String toString() => 'ApiException($status, $code)';
}

/// Talks to the clinic API. The browser keeps the session cookie; the
/// client sends it with every call (`withCredentials` on web).
class ClinicApi {
  ClinicApi(this._client, {String baseUrl = apiBaseUrl})
    : _base = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

  final http.Client _client;
  final String _base;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _base.isEmpty ? Uri.base.origin : _base;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException {
      throw const ApiException(
        0,
        'network',
        'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
      );
    }
    final text = utf8.decode(response.bodyBytes);
    final json = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 400) {
      final error = json is Json ? json['error'] : null;
      throw ApiException(
        response.statusCode,
        error is Json ? error['code'] as String? ?? 'error' : 'error',
        error is Json
            ? error['message'] as String? ?? 'Có lỗi máy chủ.'
            : 'Có lỗi máy chủ.',
      );
    }
    return json;
  }

  Future<StaffSession> login(String email, String password) async =>
      StaffSession.fromJson(
        await _send(
          'POST',
          '/v1/staff/login',
          body: {'email': email, 'password': password},
        ) as Json,
      );

  Future<void> logout() => _send('POST', '/v1/staff/logout');

  Future<StaffSession> me() async =>
      StaffSession.fromJson(await _send('GET', '/v1/staff/me') as Json);

  Future<Worklist> worklist({String? date}) async => Worklist.fromJson(
    await _send(
      'GET',
      '/v1/clinic/worklist',
      query: date == null ? null : {'date': date},
    ) as Json,
  );

  Future<ChartData> chart(String appointmentId) async => ChartData.fromJson(
    await _send('GET', '/v1/appointments/$appointmentId/chart') as Json,
  );

  Future<void> arrive(String appointmentId) =>
      _send('POST', '/v1/appointments/$appointmentId/arrive');

  Future<void> start(String appointmentId) =>
      _send('POST', '/v1/appointments/$appointmentId/start');

  Future<void> summaryFeedback(String summaryId, String value) => _send(
    'POST',
    '/v1/summaries/$summaryId/feedback',
    body: {'value': value},
  );

  Future<List<HistoryEntry>> history(String patientId) async => [
    for (final h in await _send(
      'GET',
      '/v1/patients/$patientId/history',
    ) as List<Object?>)
      HistoryEntry.fromJson(h! as Json),
  ];

  Future<Catalog> catalog() async =>
      Catalog.fromJson(await _send('GET', '/v1/clinic/catalog') as Json);

  Future<ResultDraft?> result(String appointmentId) async {
    final json = await _send('GET', '/v1/appointments/$appointmentId/result');
    return json is Json ? ResultDraft.fromJson(json) : null;
  }

  Future<ResultDraft> saveDraft(String appointmentId, Json body) async =>
      ResultDraft.fromJson(
        await _send(
          'PUT',
          '/v1/appointments/$appointmentId/result-draft',
          body: body,
        ) as Json,
      );

  Future<ResultDraft> sendResult(String appointmentId) async =>
      ResultDraft.fromJson(
        await _send('POST', '/v1/appointments/$appointmentId/result/send')
            as Json,
      );

  Future<ResultDraft> amendResult(String appointmentId, String reason) async =>
      ResultDraft.fromJson(
        await _send(
          'POST',
          '/v1/appointments/$appointmentId/result/amend',
          body: {'reason': reason},
        ) as Json,
      );
}
