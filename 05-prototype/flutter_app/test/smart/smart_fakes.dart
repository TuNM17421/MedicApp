import 'dart:async';
import 'dart:typed_data';

import 'package:medic_app/features/smart/data/smart_gateway.dart';
import 'package:medic_app/features/smart/data/voice_capture.dart';
import 'package:medic_app/features/smart/domain/smart_models.dart';

/// Server-shaped reply JSON, parsed by the real model code.
SmartReply reply({
  String status = 'ask',
  int version = 1,
  Map<String, dynamic> fields = const {},
  Map<String, dynamic>? question,
  String? notice,
  Map<String, String> sources = const {},
  List<String> changed = const [],
  bool processing = false,
  Map<String, String>? error,
}) => SmartReply.fromJson({
  'status': status,
  'draft_version': version,
  'fields': {
    'patient_id': null,
    'visit_type': null,
    'facility_id': null,
    'department_id': null,
    'department_reason': null,
    'doctor_id': null,
    'time': null,
    'symptoms': null,
    ...fields,
  },
  'sources': sources,
  'question': question,
  'notice': notice,
  'changed': changed,
  'processing': processing,
  'error': error,
});

const readyFields = {
  'patient_id': 'self',
  'visit_type': 'service',
  'facility_id': 'anbinh',
  'department_id': 'bones',
  'department_reason': 'Mô tả có nhắc tới đau khớp.',
  'time': {'kind': 'earliest', 'date': null, 'period': 'morning'},
  'symptoms': 'đau khớp gối',
};

Map<String, dynamic> askType = {
  'field': 'type',
  'text': 'Bạn muốn khám BHYT hay khám dịch vụ?',
  'options': [
    {'value': 'insurance', 'label': 'Khám BHYT'},
    {'value': 'service', 'label': 'Khám dịch vụ'},
  ],
  'allow_picker': false,
};

typedef Handler = Future<SmartReply> Function(String kind, String a, String? b);

class FakeGateway implements SmartGateway {
  FakeGateway(this.handler, {this.initial, this.voice = false, this.fail});
  final Handler handler;
  final SmartReply? initial;
  final bool voice;
  final SmartGatewayException? fail;
  SmartContext? context;
  FakeConnection? connection;

  @override
  Future<SmartConnection> start(SmartContext context) async {
    this.context = context;
    if (fail != null) throw fail!;
    return connection = FakeConnection(
      SmartSessionInfo(
        mode: voice ? 'openai' : 'mock',
        voiceAvailable: voice,
        reply: initial ?? reply(question: askType),
      ),
      handler,
    );
  }
}

class FakeConnection implements SmartConnection {
  FakeConnection(this.info, this.handler);
  @override
  final SmartSessionInfo info;
  final Handler handler;
  final calls = <String>[];
  bool closed = false;
  FakeAudioLink? link;

  @override
  Future<SmartReply> text(String text, String id) {
    calls.add('text:$text');
    return handler('text', text, null);
  }

  @override
  Future<SmartReply> choose(String field, String? value) {
    calls.add('choice:$field=$value');
    return handler('choice', field, value);
  }

  @override
  Future<SmartReply> edit(String field, String? value) {
    calls.add('edit:$field=$value');
    return handler('edit', field, value);
  }

  @override
  SmartAudioLink openAudio() => link = FakeAudioLink();

  @override
  Future<void> close() async => closed = true;
}

class FakeAudioLink implements SmartAudioLink {
  final controller = StreamController<SmartAudioEvent>.broadcast();
  final sent = <String>[];
  int bytes = 0;
  @override
  Stream<SmartAudioEvent> get events => controller.stream;
  @override
  void start() => sent.add('start');
  @override
  void sendAudio(Uint8List pcm16) => bytes += pcm16.length;
  @override
  void commit() => sent.add('commit');
  @override
  void cancelTurn() => sent.add('cancel');
  @override
  void stop() => sent.add('stop');
  @override
  Future<void> close() async => sent.add('close');
  void emit(SmartAudioEvent event) => controller.add(event);
}

class FakeCapture implements VoiceCapture {
  FakeCapture({this.granted = true});
  final bool granted;
  StreamController<Uint8List>? stream;
  int stops = 0;
  @override
  Future<bool> ensurePermission() async => granted;
  @override
  Future<Stream<Uint8List>> start() async =>
      (stream = StreamController<Uint8List>()).stream;
  @override
  Future<void> stop() async {
    stops++;
    await stream?.close();
    stream = null;
  }

  @override
  Future<void> dispose() async {}
}

/// 100 ms of PCM16 at 24 kHz with a constant amplitude.
Uint8List tone(int amplitude) {
  final data = ByteData(4800);
  for (var i = 0; i < 2400; i++) {
    data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}
