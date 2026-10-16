// Contract test app ↔ backend for bước 16 (patient sign-in, sharing consent,
// uploads), in the style of test/smart/backend_contract_test.dart. Runs only
// when asked, since it needs Node and writes a temporary clinic database:
//
//   PATIENT_CONTRACT=1 flutter test test/sharing/patient_contract_test.dart
//     starts its own backend (seeded copy in the temp folder, DEMO_OTP=000000)
//   PATIENT_API_URL=http://127.0.0.1:8080 flutter test test/sharing/patient_contract_test.dart
//     uses a running backend seeded today and started with DEMO_OTP=000000
//
// Without either it is skipped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medic_app/features/sharing/data/patient_api.dart';
import 'package:medic_app/features/sharing/domain/sharing_models.dart';
import 'package:medic_core/medic_core.dart';

const _lan = '0912000482';
const _minh = '0912000317';
const _demoOtp = '000000';

String _today() => dayKey(DateTime.now().toUtc().add(const Duration(hours: 7)));

/// Seeds a temporary database and starts the backend on it; null when Node
/// or the backend's packages are missing.
Future<(Process, String, Directory)?> _startBackend() async {
  final backend = Directory('../backend');
  if (!File('${backend.path}/node_modules/ws/package.json').existsSync()) {
    return null;
  }
  final temp = Directory.systemTemp.createTempSync('medicapp-contract');
  final env = {
    'CLINIC_DB': '${temp.path}/clinic.db',
    'SEED_TODAY': _today(),
    'DEMO_OTP': _demoOtp,
    'PATIENT_OTP_MODE': 'dev',
    'SMART_MODE': 'mock',
    'OPENAI_API_KEY': '',
  };
  try {
    final seed = await Process.run(
      'node',
      ['src/clinic/seed.js'],
      workingDirectory: backend.path,
      environment: env,
    );
    if (seed.exitCode != 0) throw StateError('seed failed: ${seed.stderr}');
  } on ProcessException {
    return null;
  }
  final port = 18100 + DateTime.now().millisecond;
  final process = await Process.start(
    'node',
    ['src/server.js'],
    workingDirectory: backend.path,
    environment: {...env, 'PORT': '$port'},
  );
  final ready = Completer<void>();
  process.stdout.transform(utf8.decoder).listen((line) {
    if (line.contains('"listening"') && !ready.isCompleted) ready.complete();
  });
  await ready.future.timeout(const Duration(seconds: 15));
  return (process, 'http://127.0.0.1:$port', temp);
}

/// The doctor web's view of a chart, to check what the clinic sees.
Future<Map<String, Object?>> _chart(
  String baseUrl,
  String appointmentId,
) async {
  final client = http.Client();
  try {
    final login = await client.post(
      Uri.parse('$baseUrl/v1/staff/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': 'bs.ha@anbinh.test',
        'password': Platform.environment['DEMO_PASSWORD'] ?? 'medicapp-demo',
      }),
    );
    expect(login.statusCode, 200, reason: login.body);
    final cookie = login.headers['set-cookie']!.split(';').first;
    final chart = await client.get(
      Uri.parse('$baseUrl/v1/appointments/$appointmentId/chart'),
      headers: {'cookie': cookie},
    );
    expect(chart.statusCode, 200, reason: chart.body);
    return jsonDecode(utf8.decode(chart.bodyBytes)) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

Future<PatientApiException> _failure(Future<Object?> call) => call.then(
  (_) => fail('expected a PatientApiException'),
  onError: (Object error) => error as PatientApiException,
);

void main() {
  final external =
      Platform.environment['PATIENT_API_URL'] ??
      const String.fromEnvironment('PATIENT_API_URL');
  final ownBackend = Platform.environment['PATIENT_CONTRACT'] == '1';

  test('patient API against the real backend', () async {
    var baseUrl = external;
    if (baseUrl.isEmpty) {
      if (!ownBackend) {
        markTestSkipped(
          'Set PATIENT_CONTRACT=1 (own backend) or PATIENT_API_URL to run.',
        );
        return;
      }
      final started = await _startBackend();
      if (started == null) {
        markTestSkipped(
          'Node backend not installed (npm install in backend/).',
        );
        return;
      }
      final (process, url, temp) = started;
      addTearDown(() {
        process.kill();
        temp.deleteSync(recursive: true);
      });
      baseUrl = url;
    }
    final api = HttpPatientApi(baseUrl: baseUrl);

    // Sign-in: the dev server shows the code; a wrong one is refused.
    final challenge = await api.requestOtp(_lan);
    expect(challenge.expiresIn, 300);
    expect(challenge.devCode, _demoOtp);
    expect((await _failure(api.requestOtp('12345'))).code, 'bad_phone');
    expect(
      (await _failure(api.createSession(_lan, '999999'))).code,
      'bad_code',
    );
    final session = await api.createSession(_lan, _demoOtp);
    expect(session.name, 'Phạm Thị Lan');
    expect(session.expiresAt.isAfter(DateTime.now()), isTrue);
    final token = session.token;

    // Today's appointment, shared in the seed.
    final list = await api.appointments(token);
    final visit = list.firstWhere((a) => dayKey(a.start) == _today());
    expect(visit.clinic.name, isNotEmpty);
    expect(visit.consent?.state, SharingState.shared);

    // Uploads with stable ids: sending the same id twice keeps one row.
    final answer = IntakeAnswer(
      id: 'pre_visit.ask',
      channel: IntakeChannel.preVisit,
      question: 'Bạn muốn hỏi bác sĩ điều gì?',
      answer: 'Kiểm tra hợp đồng app: gối có phải do gút không?',
      answeredAt: DateTime.now(),
    );
    final first = await api.putIntake(token, visit.id, [answer.toWire()]);
    expect(await api.putIntake(token, visit.id, [answer.toWire()]), first);
    expect(
      await api.putSelfMeds(token, visit.id, [
        const SelfMed(
          name: 'Paracetamol 500mg',
          how: '1 viên khi đau',
        ).toJson(),
      ]),
      1,
    );
    var chart = await _chart(baseUrl, visit.id);
    expect(
      (chart['intake']! as List).map((i) => (i as Map)['answer']),
      contains(answer.answer),
    );
    expect(chart['selfMeds'], hasLength(1));

    // Withdraw: the doctor's next load no longer shows the data, and
    // uploads are refused.
    final revoked = await api.revokeConsent(token, visit.id);
    expect(revoked.state, SharingState.revoked);
    chart = await _chart(baseUrl, visit.id);
    expect(chart['intake'], isEmpty);
    expect(chart['selfMeds'], isEmpty);
    expect(chart['summary'], isNull);
    final refused = await _failure(
      api.putIntake(token, visit.id, [answer.toWire()]),
    );
    expect(refused.code, 'consent_required');
    expect(refused.permanent, isTrue);
    expect(
      (await api.appointments(token))
          .firstWhere((a) => a.id == visit.id)
          .consent!
          .state,
      SharingState.revoked,
    );

    // Sharing again (intake only) brings the answers back.
    final again = await api.grantConsent(token, visit.id, {ShareScope.intake});
    expect(again.state, SharingState.shared);
    expect(again.scope, {ShareScope.intake});
    expect(again.expiresAt.isAfter(visit.startsAt), isTrue);
    chart = await _chart(baseUrl, visit.id);
    expect(chart['intake'], isNotEmpty);
    expect(chart['selfMeds'], isEmpty, reason: 'not in the new scope');

    // Sign-out revokes the token.
    await api.deleteSession(token);
    expect((await _failure(api.appointments(token))).code, 'unauthenticated');

    // Minh has a sent result: fetched without a code, with course ids that
    // the dose log uses.
    await api.requestOtp(_minh);
    final minh = (await api.createSession(_minh, _demoOtp)).token;
    final minhVisit = (await api.appointments(minh))
        .firstWhere((a) => a.hasResult);
    final result = await api.result(minh, minhVisit.id, profileId: 'self');
    expect(result!.visitId, minhVisit.id);
    final course = coursesFrom([result]).first;
    expect(course.id, '${minhVisit.id}#1');
    final upload = await api.postDoseEvents(minh, [
      doseEventWire(
        DoseLogEntry(
          courseId: course.id,
          day: dayKey(course.firstDay),
          slot: course.item.doses.first.slot,
          mark: DoseMark.taken,
          at: course.prescribedAt,
        ),
      ),
      doseEventWire(
        DoseLogEntry(
          courseId: 'not-a-course#1',
          day: dayKey(course.firstDay),
          slot: DoseSlot.morning,
          mark: DoseMark.skipped,
          reason: SkipReason.forgot,
          at: course.prescribedAt,
        ),
      ),
    ]);
    expect(upload.accepted, 1);
    expect(upload.ignored, ['not-a-course#1']);
    await api.deleteSession(minh);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
