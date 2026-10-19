import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/smart/data/smart_gateway.dart';
import 'package:medic_app/features/smart/domain/smart_models.dart';

final context = SmartContext(
  today: DateTime(2026, 10, 14),
  profiles: const [
    (id: 'self', relationship: 'Bản thân', age: 60),
    (id: 'mother', relationship: 'Mẹ', age: 78),
  ],
);

/// Runs the real Node backend in mock mode when Node and its packages are
/// installed; otherwise the contract test is skipped with a reason.
Future<(Process, String)?> startBackend() async {
  final backend = Directory('../backend');
  if (!File('${backend.path}/node_modules/ws/package.json').existsSync()) {
    return null;
  }
  final port = 18000 + DateTime.now().millisecond;
  final Process process;
  try {
    process = await Process.start(
      'node',
      ['src/server.js'],
      workingDirectory: backend.path,
      environment: {
        'SMART_MODE': 'mock',
        'PORT': '$port',
        'OPENAI_API_KEY': '',
      },
    );
  } on ProcessException {
    return null;
  }
  final ready = Completer<void>();
  process.stdout.transform(utf8.decoder).listen((line) {
    if (line.contains('"listening"') && !ready.isCompleted) ready.complete();
  });
  await ready.future.timeout(const Duration(seconds: 10));
  return (process, 'http://127.0.0.1:$port');
}

void main() {
  test('HTTP gateway against the real backend in mock mode', () async {
    final started = await startBackend();
    if (started == null) {
      markTestSkipped('Node backend not installed (npm install in backend/).');
      return;
    }
    final (process, url) = started;
    addTearDown(process.kill);
    final gateway = HttpSmartGateway(baseUrl: url);
    final connection = await gateway.start(context);
    expect(connection.info.simulated, isTrue);
    expect(connection.info.voiceAvailable, isFalse);
    expect(connection.info.reply.question!.field, 'patientId');

    var reply = await connection.text(
      'Tôi muốn khám dịch vụ cho tôi, đau khớp gối, ở An Bình, chiều thứ Bảy',
      't1',
    );
    expect(reply.status, SmartStatus.ready);
    expect(reply.fields.type, VisitType.service);
    expect(reply.fields.time!.date, DateTime(2026, 10, 17));
    expect(reply.fields.time!.period, 'afternoon');
    expect(reply.sources['departmentId'], 'suggested');

    reply = await connection.edit('time', 'date:2026-10-19:morning');
    expect(reply.fields.time!.wire, 'date:2026-10-19:morning');
    expect(reply.sources['time'], 'manual');

    reply = await connection.choose('patientId', 'mother');
    expect(reply.fields.symptoms, isNull);
    expect(reply.question!.field, 'departmentId');

    await expectLater(
      connection.choose('facilityId', 'nowhere'),
      throwsA(isA<SmartGatewayException>()),
    );

    final audio = connection.openAudio();
    final first = await audio.events.first;
    expect(first, isA<AudioError>());
    expect((first as AudioError).code, 'stt_unavailable');
    await audio.close();
    await connection.close();
    await expectLater(
      connection.text('nữa', 't2'),
      throwsA(
        isA<SmartGatewayException>().having(
          (e) => e.code,
          'code',
          'session_not_found',
        ),
      ),
    );
  });

  test('unreachable backend maps to a friendly error', () async {
    final gateway = HttpSmartGateway(
      baseUrl: 'http://127.0.0.1:9',
      client: MockClient((_) => throw http.ClientException('refused')),
    );
    await expectLater(
      gateway.start(context),
      throwsA(
        isA<SmartGatewayException>().having((e) => e.code, 'code', 'network'),
      ),
    );
  });
}
