import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/meds/application/meds_providers.dart';
import 'package:medic_app/features/meds/data/med_reminder_scheduler.dart';
import 'package:medic_app/features/sharing/application/sharing_providers.dart';
import 'package:medic_app/features/sharing/data/patient_api.dart';
import 'package:medic_app/features/sharing/domain/outbox.dart';
import 'package:medic_app/features/sharing/domain/sharing_models.dart';
import 'package:medic_core/medic_core.dart';

import 'sharing_fakes.dart';

Map<String, Object?> _event(String course, String day, String mark) => {
  'courseId': course,
  'day': day,
  'slot': 'morning',
  'mark': mark,
  'reason': null,
  'at': '${day}T07:05:00+07:00',
};

OutboxItem _doses(List<Map<String, Object?>> events) =>
    OutboxItem(kind: OutboxKind.doses, body: {'events': events});

IntakeAnswer _answer(String text) => IntakeAnswer(
  id: 'pre_visit.ask',
  channel: IntakeChannel.preVisit,
  question: 'Bạn muốn hỏi bác sĩ điều gì?',
  answer: text,
  answeredAt: DateTime(2026, 10, 16, 8),
);

/// Lets queued uploads finish.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('enqueue', () {
    test('intake replaces what waits for the same visit', () {
      var queue = enqueue(
        const [],
        const OutboxItem(
          kind: OutboxKind.intake,
          appointmentId: 'a1',
          body: {'answers': []},
        ),
      );
      queue = enqueue(queue, _doses([_event('a1#1', '2026-10-15', 'taken')]));
      queue = enqueue(
        queue,
        const OutboxItem(
          kind: OutboxKind.intake,
          appointmentId: 'a1',
          body: {
            'answers': [{}],
          },
        ),
      );
      expect(queue.map((item) => item.kind), [
        OutboxKind.doses,
        OutboxKind.intake,
      ]);
      expect(queue.last.body['answers'], hasLength(1));
    });

    test('dose marks merge; the newest mark of a dose wins', () {
      var queue = enqueue(
        const [],
        _doses([_event('a1#1', '2026-10-15', 'taken')]),
      );
      queue = enqueue(
        queue,
        _doses([
          _event('a1#1', '2026-10-15', 'skipped'),
          _event('a1#1', '2026-10-16', 'taken'),
        ]),
      );
      expect(queue.single.events.map((e) => e['mark']), ['skipped', 'taken']);
    });

    test('dose batches stay within 500 events', () {
      final queue = enqueue(
        const [],
        _doses([
          for (var i = 0; i < 1200; i++) _event('a1#$i', '2026-10-15', 'taken'),
        ]),
      );
      expect(queue.map((item) => item.events.length), [500, 500, 200]);
    });

    test('survives the vault round trip', () {
      final item = _doses([_event('a1#1', '2026-10-15', 'taken')]).retried();
      final back = OutboxItem.fromJson(item.toJson());
      expect(back.kind, OutboxKind.doses);
      expect(back.attempts, 1);
      expect(back.events.single['courseId'], 'a1#1');
    });
  });

  group('OutboxController', () {
    late FakePatientApi api;
    setUp(() => api = FakePatientApi());

    ProviderContainer open({List<ServerAppointment>? appointments}) {
      final c = signedInContainer(
        api,
        snapshot: signedInSnapshot(appointments: appointments),
        extra: [
          pendingDoseStoreProvider.overrideWithValue(MemoryPendingDoseStore()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('keeps an item while offline and sends it on the next try', () async {
      final c = open(appointments: [lanVisit(consent: sharedConsent())]);
      api.uploadFailure = PatientApiException.network;
      c.read(intakeAnswersProvider.notifier).save('a-p2', [_answer('Gối?')]);
      await _settle();
      expect(api.calls, ['intake a-p2']);
      expect(c.read(outboxProvider).single.attempts, 1);
      expect(
        c.read(mockAccountStoreProvider)[lanPhone]!.outbox,
        hasLength(1),
        reason: 'the queue is kept with the account',
      );

      api.uploadFailure = null;
      await c.read(outboxProvider.notifier).flush();
      expect(c.read(outboxProvider), isEmpty);
      expect(api.intake['a-p2']!.single['answer'], 'Gối?');
      expect(c.read(mockAccountStoreProvider)[lanPhone]!.outbox, isEmpty);
    });

    test('403 consent_required drops the item', () async {
      final c = open(appointments: [lanVisit(consent: sharedConsent())]);
      api.uploadFailure = const PatientApiException(
        'consent_required',
        'Bạn chưa đồng ý chia sẻ mục này với phòng khám.',
        status: 403,
      );
      c.read(intakeAnswersProvider.notifier).save('a-p2', [_answer('Gối?')]);
      await _settle();
      expect(api.calls, ['intake a-p2']);
      expect(c.read(outboxProvider), isEmpty);
    });

    test('a waiting queue is sent after an app restart', () async {
      final c = open(appointments: [lanVisit(consent: sharedConsent())]);
      api.uploadFailure = PatientApiException.server;
      c.read(intakeAnswersProvider.notifier).save('a-p2', [_answer('Gối?')]);
      await _settle();
      final saved = c.read(mockAccountStoreProvider)[lanPhone]!;

      final restarted = FakePatientApi();
      final next = signedInContainer(
        restarted,
        snapshot: {
          'v': 1,
          'accounts': [saved.toJson()],
          'session': lanPhone,
        },
      );
      addTearDown(next.dispose);
      expect(next.read(outboxProvider), hasLength(1));
      await next.read(serverAppointmentsProvider.notifier).sync();
      expect(restarted.calls, ['appointments', 'intake a-p2']);
      expect(next.read(outboxProvider), isEmpty);
    });

    test('answers are not sent without a consent for them', () async {
      final c = open(
        appointments: [
          lanVisit(consent: sharedConsent(scope: {ShareScope.doseLog})),
        ],
      );
      c.read(intakeAnswersProvider.notifier).save('a-p2', [_answer('Gối?')]);
      await _settle();
      expect(api.calls, isEmpty);
      expect(c.read(outboxProvider), isEmpty);
    });

    test('a new dose mark of a clinic prescription is sent', () async {
      final c = open(appointments: [lanVisit(consent: sharedConsent())]);
      c.read(doseLogProvider.notifier).taken('a-p2#1|2026-10-16|morning');
      // A course of the app's own (mock) visit means nothing to the clinic.
      c.read(doseLogProvider.notifier).taken('V1#1|2026-10-16|morning');
      await _settle();
      expect(api.calls, ['doses 1']);
      expect(api.doseEvents.single, {
        'courseId': 'a-p2#1',
        'day': '2026-10-16',
        'slot': 'morning',
        'mark': 'taken',
        'reason': null,
        'at': '2026-10-16T09:00:00+07:00',
      });
    });

    test('nothing is sent while no clinic shares the dose log', () async {
      final c = open();
      c.read(doseLogProvider.notifier).taken('a-p2#1|2026-10-16|morning');
      await _settle();
      expect(api.calls, isEmpty);
    });

    test('sharing sends the answers and 30 days of marks', () async {
      final c = open();
      c.read(intakeAnswersProvider.notifier).save('a-p2', [_answer('Gối?')]);
      final log = c.read(doseLogProvider.notifier);
      log.taken('a-p2#1|2026-10-15|morning');
      log.skipped('a-p2#1|2026-10-16|morning', SkipReason.forgot);
      log.taken('a-p2#1|2026-08-01|morning'); // older than 30 days
      await _settle();
      expect(api.calls, isEmpty);

      await c.read(serverAppointmentsProvider.notifier).share('a-p2', {
        ShareScope.intake,
        ShareScope.doseLog,
        ShareScope.selfMeds,
      });
      await _settle();
      expect(api.calls, [
        'grant a-p2 intake,dose_log,self_meds',
        'intake a-p2',
        'doses 2',
      ]);
      expect(
        c.read(serverAppointmentProvider('a-p2'))!.consent!.state,
        SharingState.shared,
      );
    });

    test('withdrawing drops the visit\'s waiting uploads', () async {
      final c = open(appointments: [lanVisit(consent: sharedConsent())]);
      api.uploadFailure = PatientApiException.network;
      c.read(intakeAnswersProvider.notifier).save('a-p2', [_answer('Gối?')]);
      await _settle();
      expect(c.read(outboxProvider), hasLength(1));

      await c.read(serverAppointmentsProvider.notifier).withdraw('a-p2');
      expect(c.read(outboxProvider), isEmpty);
      expect(
        c.read(serverAppointmentProvider('a-p2'))!.consent!.state,
        SharingState.revoked,
      );
    });

    test('clinic appointments join the app\'s own list', () async {
      final c = open();
      api.appointmentsToReturn = [lanVisit(status: 'arrived')];
      await c.read(serverAppointmentsProvider.notifier).refresh();
      final record = c.read(appointmentsProvider).records.single;
      expect(record.visit.id, 'a-p2');
      expect(record.visit.facilityName, 'Phòng khám Đa khoa An Bình');
      expect(record.visit.date, DateTime(2026, 10, 16));
      expect(record.visit.patientId, 'mother');
    });

    test('an expired session signs out', () async {
      final c = open();
      final failing = _Unauthenticated();
      final next = signedInContainer(failing);
      addTearDown(next.dispose);
      expect(next.read(authSessionProvider), lanPhone);
      await next.read(serverAppointmentsProvider.notifier).refresh();
      expect(next.read(authSessionProvider), isNull);
      expect(next.read(mockAccountStoreProvider)[lanPhone]!.session, isNull);
      expect(c.read(authSessionProvider), lanPhone);
    });

    test('sign-out deletes the clinic session', () async {
      final c = open();
      c.read(authSessionProvider.notifier).signOut();
      await _settle();
      expect(api.calls, ['delete tok']);
      expect(c.read(mockAccountStoreProvider)[lanPhone]!.session, isNull);
    });
  });
}

class _Unauthenticated extends FakePatientApi {
  @override
  Future<List<ServerAppointment>> appointments(
    String token, {
    String fallbackName = '',
  }) async => throw const PatientApiException(
    'unauthenticated',
    'Phiên đăng nhập đã hết.',
    status: 401,
  );
}
