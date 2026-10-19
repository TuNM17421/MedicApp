import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/family_models.dart';

/// Why a call to the family API failed. [message] is ready to show.
class FamilyApiException implements Exception {
  const FamilyApiException(this.code, this.message, {this.status});
  final String code, message;
  final int? status;

  static const network = FamilyApiException(
    'network',
    'Chưa kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
  );
  static const server = FamilyApiException(
    'server',
    'Máy chủ chưa trả lời được. Bạn thử lại sau ít phút nhé.',
  );

  /// The link is gone for this phone: ended, or the token is no longer known.
  bool get linkGone => code == 'link_ended' || code == 'unauthenticated';

  @override
  String toString() => 'FamilyApiException($code, $status)';
}

const _messages = {
  'bad_code':
      'Mã liên kết chưa đúng hoặc đã hết hạn. Nhờ người thân tạo mã mới.',
  'rate_limited': 'Bạn đã thử nhiều lần. Vui lòng đợi ít phút rồi thử lại.',
  'link_ended': 'Liên kết này đã được hủy.',
  'unauthenticated': 'Liên kết này không còn hiệu lực trên máy bạn.',
  'already_linked': 'Hồ sơ này đã liên kết với một máy.',
};

/// The link as the server sees it.
class FamilyLinkInfo {
  const FamilyLinkInfo({
    required this.id,
    required this.status,
    required this.ownerName,
    this.memberName,
    this.shareMissed = true,
  });
  final String id, ownerName;
  final String? memberName;
  final FamilyLinkStatus status;
  final bool shareMissed;

  factory FamilyLinkInfo.fromJson(Map<String, Object?> json) => FamilyLinkInfo(
    id: json['id']! as String,
    status: FamilyLinkStatus.values.byName(json['status']! as String),
    ownerName: json['ownerName']! as String,
    memberName: json['memberName'] as String?,
    shareMissed: json['shareMissed'] as bool? ?? true,
  );
}

class FamilyInvite {
  const FamilyInvite({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;

  factory FamilyInvite.fromJson(Map<String, Object?> json) => FamilyInvite(
    code: json['code']! as String,
    expiresAt: DateTime.parse(json['expiresAt']! as String),
  );
}

/// Who made a code, shown before the member agrees.
class FamilyInviter {
  const FamilyInviter({required this.ownerName, required this.relationship});
  final String ownerName;

  /// How the owner's profile calls the member: "Mẹ".
  final String relationship;
}

class FamilyEvent {
  const FamilyEvent({
    required this.seq,
    required this.kind,
    required this.id,
    this.body = const {},
  });
  final int seq;
  final String kind, id;
  final Map<String, Object?> body;
}

class FamilyFeed {
  const FamilyFeed({
    required this.status,
    required this.cursor,
    required this.events,
    this.more = false,
  });
  final FamilyLinkStatus status;
  final int cursor;
  final List<FamilyEvent> events;
  final bool more;
}

/// The family side of the local backend (FAMILY-API.md).
abstract class FamilyApi {
  Future<({FamilyLinkInfo link, String token, FamilyInvite invite})> create({
    required String ownerName,
    required Map<String, Object?> profile,
  });
  Future<FamilyInvite> reinvite(String id, String token);
  Future<FamilyInviter> peek(String code);
  Future<({FamilyLinkInfo link, String token})> claim({
    required String code,
    required String memberName,
    required bool shareMissed,
  });
  Future<FamilyLinkInfo> view(String id, String token);
  Future<void> end(String id, String token);
  Future<void> setShareMissed(String id, String token, bool value);
  Future<void> post(String id, String token, List<Map<String, Object?>> events);
  Future<FamilyFeed> read(String id, String token, {int after = 0});
  Future<void> putDoses(
    String id,
    String token, {
    required List<Map<String, Object?>> doses,
    required List<Map<String, Object?>> marks,
  });
}

class HttpFamilyApi implements FamilyApi {
  HttpFamilyApi({required this.baseUrl, http.Client? client})
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
      throw FamilyApiException.network;
    }
    Object? decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) return decoded;
    final code = switch (decoded) {
      {'error': {'code': final String code}} => code,
      _ => status == 401 ? 'unauthenticated' : 'server',
    };
    throw FamilyApiException(
      code,
      _messages[code] ?? FamilyApiException.server.message,
      status: status,
    );
  }

  T _read<T>(Object? body, T Function(Map<String, Object?>) parse) {
    try {
      return parse((body! as Map).cast<String, Object?>());
    } on Object {
      throw FamilyApiException.server;
    }
  }

  Map<String, Object?> _map(Object? value) =>
      (value! as Map).cast<String, Object?>();

  String _link(String id) => '/v1/family/links/${Uri.encodeComponent(id)}';

  @override
  Future<({FamilyLinkInfo link, String token, FamilyInvite invite})> create({
    required String ownerName,
    required Map<String, Object?> profile,
  }) async {
    final body = await _send(
      'POST',
      '/v1/family/links',
      body: {'ownerName': ownerName, 'profile': profile},
    );
    return _read(
      body,
      (json) => (
        link: FamilyLinkInfo.fromJson(_map(json['link'])),
        token: json['token']! as String,
        invite: FamilyInvite.fromJson(_map(json['invite'])),
      ),
    );
  }

  @override
  Future<FamilyInvite> reinvite(String id, String token) async {
    final body = await _send('POST', '${_link(id)}/invite', token: token);
    return _read(body, (json) => FamilyInvite.fromJson(_map(json['invite'])));
  }

  @override
  Future<FamilyInviter> peek(String code) async {
    final body = await _send('POST', '/v1/family/peek', body: {'code': code});
    return _read(
      body,
      (json) => FamilyInviter(
        ownerName: json['ownerName']! as String,
        relationship: _map(json['profile'])['relationship']! as String,
      ),
    );
  }

  @override
  Future<({FamilyLinkInfo link, String token})> claim({
    required String code,
    required String memberName,
    required bool shareMissed,
  }) async {
    final body = await _send(
      'POST',
      '/v1/family/claim',
      body: {
        'code': code,
        'memberName': memberName,
        'shareMissed': shareMissed,
      },
    );
    return _read(
      body,
      (json) => (
        link: FamilyLinkInfo.fromJson(_map(json['link'])),
        token: json['token']! as String,
      ),
    );
  }

  @override
  Future<FamilyLinkInfo> view(String id, String token) async {
    final body = await _send('GET', _link(id), token: token);
    return _read(body, FamilyLinkInfo.fromJson);
  }

  @override
  Future<void> end(String id, String token) =>
      _send('DELETE', _link(id), token: token);

  @override
  Future<void> setShareMissed(String id, String token, bool value) => _send(
    'PUT',
    '${_link(id)}/settings',
    token: token,
    body: {'shareMissed': value},
  );

  @override
  Future<void> post(
    String id,
    String token,
    List<Map<String, Object?>> events,
  ) => _send(
    'POST',
    '${_link(id)}/events',
    token: token,
    body: {'events': events},
  );

  @override
  Future<FamilyFeed> read(String id, String token, {int after = 0}) async {
    final body = await _send(
      'GET',
      '${_link(id)}/events?after=$after',
      token: token,
    );
    return _read(
      body,
      (json) => FamilyFeed(
        status: FamilyLinkStatus.values.byName(json['status']! as String),
        cursor: (json['cursor']! as num).toInt(),
        more: json['more'] as bool? ?? false,
        events: [
          for (final raw in json['events']! as List<Object?>)
            FamilyEvent(
              seq: (_map(raw)['seq']! as num).toInt(),
              kind: _map(raw)['kind']! as String,
              id: _map(raw)['id']! as String,
              body: _map(_map(raw)['body'] ?? const {}),
            ),
        ],
      ),
    );
  }

  @override
  Future<void> putDoses(
    String id,
    String token, {
    required List<Map<String, Object?>> doses,
    required List<Map<String, Object?>> marks,
  }) => _send(
    'PUT',
    '${_link(id)}/doses',
    token: token,
    body: {'doses': doses, 'marks': marks},
  );
}
