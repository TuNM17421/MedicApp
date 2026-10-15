import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/smart_models.dart';

/// Talks to the local Smart Scheduling backend. The app never holds an
/// OpenAI key; it only knows the backend URL and a per-session token.
abstract interface class SmartGateway {
  Future<SmartConnection> start(SmartContext context);
}

abstract interface class SmartConnection {
  SmartSessionInfo get info;
  Future<SmartReply> text(String text, String clientTurnId);
  Future<SmartReply> choose(String field, String? value);
  Future<SmartReply> edit(String field, String? value);
  SmartAudioLink openAudio();
  Future<void> close();
}

const _unreachable = SmartGatewayException(
  'network',
  'Chưa kết nối được dịch vụ Đặt lịch thông minh. Bạn có thể thử lại hoặc đặt lịch từng bước.',
);

class HttpSmartGateway implements SmartGateway {
  HttpSmartGateway({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  @override
  Future<SmartConnection> start(SmartContext context) async {
    final body = await _send(
      () => _client.post(
        Uri.parse('$baseUrl/v1/smart/sessions'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(context.toJson()),
      ),
    );
    return _HttpConnection(
      this,
      body['session_id'] as String,
      body['token'] as String,
      SmartSessionInfo(
        mode: body['mode'] as String? ?? 'mock',
        voiceAvailable: body['voice_available'] == true,
        reply: SmartReply.fromJson(
          (body['reply'] as Map).cast<String, dynamic>(),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw _unreachable;
    } on http.ClientException {
      throw _unreachable;
    } on Exception {
      throw _unreachable;
    }
    final Map<String, dynamic> body;
    try {
      body = response.body.isEmpty
          ? const {}
          : (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
                .cast<String, dynamic>();
    } on FormatException {
      throw _unreachable;
    }
    if (response.statusCode >= 400) {
      final error = (body['error'] as Map?)?.cast<String, dynamic>() ?? {};
      throw SmartGatewayException(
        error['code'] as String? ?? 'http_${response.statusCode}',
        error['message'] as String? ?? _unreachable.message,
      );
    }
    return body;
  }
}

class _HttpConnection implements SmartConnection {
  _HttpConnection(this._gateway, this._id, this._token, this.info);
  final HttpSmartGateway _gateway;
  final String _id, _token;
  @override
  final SmartSessionInfo info;

  Uri _uri(String path) =>
      Uri.parse('${_gateway.baseUrl}/v1/smart/sessions/$_id$path');

  Future<SmartReply> _turn(Map<String, dynamic> body) async =>
      SmartReply.fromJson(
        await _gateway._send(
          () => _gateway._client.post(
            _uri('/turns'),
            headers: {
              'content-type': 'application/json',
              'x-session-token': _token,
            },
            body: jsonEncode(body),
          ),
        ),
      );

  @override
  Future<SmartReply> text(String text, String clientTurnId) =>
      _turn({'kind': 'text', 'text': text, 'client_turn_id': clientTurnId});
  @override
  Future<SmartReply> choose(String field, String? value) =>
      _turn({'kind': 'choice', 'field': field, 'value': value});
  @override
  Future<SmartReply> edit(String field, String? value) =>
      _turn({'kind': 'edit', 'field': field, 'value': value});

  @override
  SmartAudioLink openAudio() {
    final base = Uri.parse(_gateway.baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/smart/sessions/$_id/audio',
      queryParameters: {'token': _token},
    );
    return _WsAudioLink(WebSocketChannel.connect(uri));
  }

  @override
  Future<void> close() async {
    try {
      await _gateway._client
          .delete(_uri(''), headers: {'x-session-token': _token})
          .timeout(const Duration(seconds: 5));
    } on Exception {
      // The server also expires idle sessions; nothing to show the user.
    }
  }
}

class _WsAudioLink implements SmartAudioLink {
  _WsAudioLink(this._channel) {
    _channel.stream.listen(
      (data) {
        if (data is! String) return;
        final event = (jsonDecode(data) as Map).cast<String, dynamic>();
        final parsed = switch (event['type']) {
          'session.ready' => const AudioReady(),
          'transcript.delta' => TranscriptDelta(
            event['turn_id'] as String,
            event['text'] as String? ?? '',
          ),
          'transcript.final' => TranscriptFinal(
            event['turn_id'] as String,
            event['text'] as String? ?? '',
          ),
          'turn.result' => TurnResult(SmartReply.fromJson(event)),
          'turn.empty' => TurnEmpty(event['turn_id'] as String? ?? ''),
          'limit.warning' => AudioWarning(
            event['reason'] as String? ?? '',
            (event['remaining_seconds'] as num?)?.toInt(),
          ),
          'audio.stopped' => AudioStopped(event['reason'] as String? ?? ''),
          'session.error' => AudioError(
            event['code'] as String? ?? 'stt_error',
            event['message'] as String? ?? _unreachable.message,
          ),
          _ => null,
        };
        if (parsed != null) _events.add(parsed);
      },
      onError: (_) => _events.add(AudioError('network', _unreachable.message)),
      onDone: () {
        if (!_closed) _events.add(const AudioStopped('closed'));
        _events.close();
      },
    );
  }
  final WebSocketChannel _channel;
  final _events = StreamController<SmartAudioEvent>.broadcast();
  bool _closed = false;

  void _json(Map<String, dynamic> event) {
    if (!_closed) _channel.sink.add(jsonEncode(event));
  }

  @override
  Stream<SmartAudioEvent> get events => _events.stream;
  @override
  void start() => _json({'type': 'audio.start'});
  @override
  void sendAudio(Uint8List pcm16) {
    if (!_closed) _channel.sink.add(pcm16);
  }

  @override
  void commit() => _json({'type': 'turn.commit'});
  @override
  void cancelTurn() => _json({'type': 'turn.cancel'});
  @override
  void stop() => _json({'type': 'audio.stop'});
  @override
  Future<void> close() async {
    _closed = true;
    await _channel.sink.close();
  }
}
