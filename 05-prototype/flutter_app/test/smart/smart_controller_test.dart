import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/data/booking_catalog.dart';
import 'package:medic_app/features/booking/data/booking_repository.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/smart/application/silence_detector.dart';
import 'package:medic_app/features/smart/application/smart_controller.dart';
import 'package:medic_app/features/smart/domain/smart_models.dart';

import 'smart_fakes.dart';

final today = DateTime(2026, 10, 14);

ProviderContainer smartContainer(
  FakeGateway gateway, {
  FakeCapture? capture,
  DemoOptions options = const DemoOptions(),
}) {
  final c = ProviderContainer(
    overrides: [
      bookingTodayProvider.overrideWithValue(today),
      bookingRepositoryProvider.overrideWith(
        (ref) => MockBookingRepository(
          today: today,
          options: () => ref.read(demoOptionsProvider),
          delay: Duration.zero,
        ),
      ),
      smartGatewayProvider.overrideWithValue(gateway),
      voiceCaptureProvider.overrideWithValue(capture ?? FakeCapture()),
    ],
  );
  c.read(demoOptionsProvider.notifier).set(options);
  c.listen(smartControllerProvider, (_, _) {});
  addTearDown(c.dispose);
  return c;
}

Future<SmartController> started(ProviderContainer c) async {
  final actions = c.read(smartControllerProvider.notifier);
  await actions.start(const SmartEntry());
  return actions;
}

void main() {
  test('session context carries ages and relationships, never names', () async {
    final gateway = FakeGateway((_, _, _) async => reply());
    final c = smartContainer(gateway);
    await started(c);
    final json = jsonEncode(gateway.context!.toJson());
    expect(json, contains('"relationship":"Mẹ"'));
    expect(json, contains('"age":78'));
    expect(json, isNot(contains('Phạm')));
    expect(c.read(smartControllerProvider).simulated, isTrue);
    expect(c.read(smartControllerProvider).phase, SmartPhase.ready);
  });

  test(
    'a ready reply becomes one proposal using the earliest morning slot',
    () async {
      final gateway = FakeGateway(
        (_, _, _) async =>
            reply(status: 'ready', version: 2, fields: readyFields),
      );
      final c = smartContainer(gateway);
      final actions = await started(c);
      await actions.sendText('Tôi đau khớp gối, khám sáng sớm nhất ở An Bình');
      final s = c.read(smartControllerProvider);
      expect(s.phase, SmartPhase.proposal);
      final draft = s.proposal!.draft;
      expect(draft.firstMissing, isNull);
      expect(int.parse(draft.slot!.time.split(':').first), lessThan(12));
      expect(s.proposal!.fee, 250000);
      expect(s.canConfirm, isTrue);
    },
  );

  test(
    'a late reply for an older version never replaces a newer one (AC06)',
    () async {
      final slow = Completer<SmartReply>();
      var n = 0;
      final gateway = FakeGateway((kind, _, _) {
        n++;
        if (n == 1) return slow.future;
        return Future.value(reply(version: 5, question: askType));
      });
      final c = smartContainer(gateway);
      final actions = await started(c);
      final first = actions.sendText('một');
      await actions.sendText('hai');
      slow.complete(reply(status: 'ready', version: 3, fields: readyFields));
      await first;
      final s = c.read(smartControllerProvider);
      expect(s.version, 5);
      expect(s.proposal, isNull);
      expect(s.phase, SmartPhase.asking);
      // Superseded results are dropped too.
      await gateway.connection!.handler('text', '', null);
    },
  );

  test(
    'confirm re-validates and hands a complete draft to payment (AC09)',
    () async {
      final gateway = FakeGateway(
        (_, _, _) async =>
            reply(status: 'ready', version: 2, fields: readyFields),
      );
      final c = smartContainer(gateway);
      final actions = await started(c);
      await actions.sendText('đủ thông tin');
      final handoff = await actions.confirm();
      expect(handoff, isNotNull);
      expect(handoff!.stage, BookingStage.payment);
      expect(handoff.draft.slot, isNotNull);
      expect(
        handoff.draft.method,
        isNull,
        reason: 'payment method stays with the user',
      );
      expect(c.read(smartControllerProvider).phase, SmartPhase.handedOff);
      expect(gateway.connection!.closed, isTrue);
    },
  );

  test(
    'a slot lost at confirmation returns to an updated proposal (AC10)',
    () async {
      final gateway = FakeGateway(
        (_, _, _) async =>
            reply(status: 'ready', version: 2, fields: readyFields),
      );
      final c = smartContainer(
        gateway,
        options: const DemoOptions(slotTaken: true),
      );
      final actions = await started(c);
      await actions.sendText('đủ thông tin');
      final before = c.read(smartControllerProvider).proposal!.draft.slot!;
      expect(await actions.confirm(), isNull);
      final s = c.read(smartControllerProvider);
      expect(s.phase, SmartPhase.proposal);
      expect(s.notice, contains('vừa hết chỗ'));
      expect(s.proposal!.draft.slot!.key, isNot(before.key));
      expect(await actions.confirm(), isNotNull);
    },
  );

  test(
    'edits are sent as manual values and Undo restores the previous one (AC07)',
    () async {
      var version = 2;
      var department = 'bones';
      final gateway = FakeGateway((kind, field, value) async {
        if (kind == 'edit' && field == 'departmentId') department = value!;
        return reply(
          status: 'ready',
          version: ++version,
          fields: {...readyFields, 'department_id': department},
          changed: kind == 'edit' ? [field] : const [],
        );
      });
      final c = smartContainer(gateway);
      final actions = await started(c);
      await actions.sendText('đủ');
      await actions.edit('departmentId', 'eyes');
      expect(
        c.read(smartControllerProvider).proposal!.draft.departmentId,
        'eyes',
      );
      expect(c.read(smartControllerProvider).changed, ['departmentId']);
      expect(c.read(smartControllerProvider).canUndo, isTrue);
      await actions.undo();
      expect(gateway.connection!.calls.last, 'edit:departmentId=bones');
      expect(
        c.read(smartControllerProvider).proposal!.draft.departmentId,
        'bones',
      );
      expect(c.read(smartControllerProvider).canUndo, isFalse);
    },
  );

  Future<SmartState> askFor(Map<String, dynamic> time) async {
    final gateway = FakeGateway(
      (_, _, _) async => reply(
        status: 'ready',
        version: 2,
        fields: {...readyFields, 'time': time},
      ),
    );
    final c = smartContainer(gateway);
    final actions = await started(c);
    await actions.sendText('Tôi đau khớp gối, khám hôm đó ở An Bình');
    return c.read(smartControllerProvider);
  }

  String iso(DateTime d) => d.toIso8601String().substring(0, 10);

  test('a full day is explained and left out of the other days', () async {
    final full = BookingCatalog.dates(today)[2];
    final s = await askFor({
      'kind': 'date',
      'date': iso(full),
      'period': 'morning',
    });
    expect(s.phase, SmartPhase.asking);
    expect(s.question!.field, 'time');
    expect(s.messages.last.fromUser, isFalse);
    expect(
      s.messages.last.text,
      'Thứ Bảy 17/10 đã kín lịch. Bạn muốn khám khi nào?',
    );
    final values = s.question!.options.map((o) => o.value);
    expect(values.first, 'earliest');
    expect(values, isNot(contains('date:${iso(full)}')));
  });

  test('a full morning offers the same afternoon first', () async {
    // In the mock schedule, Cơ Xương Khớp at An Bình has only afternoon
    // slots left on 21/10.
    final s = await askFor({
      'kind': 'date',
      'date': '2026-10-21',
      'period': 'morning',
    });
    expect(
      s.messages.last.text,
      'Buổi sáng Thứ Tư 21/10 đã kín. Buổi chiều cùng ngày còn chỗ, hoặc bạn chọn ngày khác.',
    );
    final first = s.question!.options.first;
    expect(first.value, 'date:2026-10-21:afternoon');
    expect(first.label, 'Chiều Thứ Tư 21/10');
    expect(
      s.question!.options.map((o) => o.value),
      isNot(contains('date:${iso(BookingCatalog.dates(today)[2])}')),
    );
  });

  test('urgent replies block the booking path (AC14)', () async {
    final gateway = FakeGateway(
      (_, _, _) async =>
          reply(status: 'urgent', version: 2, fields: readyFields),
    );
    final c = smartContainer(gateway);
    final actions = await started(c);
    await actions.sendText('khó thở');
    final s = c.read(smartControllerProvider);
    expect(s.phase, SmartPhase.urgent);
    expect(s.canConfirm, isFalse);
    expect(await actions.confirm(), isNull);
  });

  test(
    'unreachable backend shows the error state with alternatives (AC13)',
    () async {
      final c = smartContainer(
        FakeGateway(
          (_, _, _) async => reply(),
          fail: const SmartGatewayException('network', 'Chưa kết nối được.'),
        ),
      );
      await started(c);
      final s = c.read(smartControllerProvider);
      expect(s.phase, SmartPhase.error);
      expect(s.error, 'Chưa kết nối được.');
    },
  );

  test('without microphone permission typing still works (AC04)', () async {
    final gateway = FakeGateway((_, _, _) async => reply(), voice: true);
    final c = smartContainer(gateway, capture: FakeCapture(granted: false));
    final actions = await started(c);
    await actions.startListening();
    final s = c.read(smartControllerProvider);
    expect(s.micOn, isFalse);
    expect(s.notice, contains('quyền dùng micro'));
    expect(gateway.connection!.link, isNull, reason: 'no audio is sent');
  });

  test('mock mode says voice is unavailable instead of pretending', () async {
    final c = smartContainer(FakeGateway((_, _, _) async => reply()));
    final actions = await started(c);
    await actions.startListening();
    expect(c.read(smartControllerProvider).notice, contains('Mô phỏng AI'));
  });

  test(
    'voice turn: live text, silence commit, final and auto-processing (AC01)',
    () async {
      final capture = FakeCapture();
      final gateway = FakeGateway((_, _, _) async => reply(), voice: true);
      final c = smartContainer(gateway, capture: capture);
      final actions = await started(c);
      await actions.startListening();
      final link = gateway.connection!.link!;
      expect(link.sent, ['start']);
      expect(c.read(smartControllerProvider).phase, SmartPhase.connecting);
      link.emit(const AudioReady());
      await pumpEventQueue();
      expect(c.read(smartControllerProvider).phase, SmartPhase.listening);
      for (var i = 0; i < 5; i++) {
        capture.stream!.add(tone(4000));
      }
      for (var i = 0; i < 20; i++) {
        capture.stream!.add(tone(10));
      }
      await pumpEventQueue();
      expect(link.sent, contains('commit'), reason: 'silence ends the turn');
      expect(link.bytes, greaterThan(0));
      link.emit(const TranscriptDelta('a1', 'Tôi đau'));
      await pumpEventQueue();
      expect(c.read(smartControllerProvider).partial, 'Tôi đau');
      link.emit(const TranscriptFinal('a1', 'Tôi đau khớp gối'));
      await pumpEventQueue();
      expect(
        c.read(smartControllerProvider).messages.last.text,
        'Tôi đau khớp gối',
      );
      expect(c.read(smartControllerProvider).processing, isTrue);
      link.emit(
        TurnResult(reply(status: 'ready', version: 3, fields: readyFields)),
      );
      await pumpEventQueue();
      final s = c.read(smartControllerProvider);
      expect(
        s.micOn,
        isFalse,
        reason: 'microphone stops when the proposal shows',
      );
      expect(link.sent, contains('stop'));
      expect(capture.stops, greaterThan(0));
      expect(s.phase, SmartPhase.proposal);
    },
  );

  test(
    'the controller releases the microphone and session on dispose (AC12)',
    () async {
      final capture = FakeCapture();
      final gateway = FakeGateway((_, _, _) async => reply(), voice: true);
      final c = smartContainer(gateway, capture: capture);
      final actions = await started(c);
      await actions.startListening();
      gateway.connection!.link!.emit(const AudioReady());
      await pumpEventQueue();
      c.dispose();
      await pumpEventQueue();
      expect(capture.stops, greaterThan(0));
      expect(gateway.connection!.closed, isTrue);
      expect(gateway.connection!.link!.sent, contains('close'));
    },
  );

  test('basic flow fallback keeps valid choices only (AC16)', () async {
    final gateway = FakeGateway(
      (_, _, _) async => reply(
        status: 'ask',
        version: 2,
        fields: {
          'patient_id': 'mother',
          'visit_type': 'insurance',
          'facility_id': 'songxanh',
          'department_id': 'heart',
        },
        question: askType,
      ),
    );
    final c = smartContainer(gateway);
    final actions = await started(c);
    await actions.sendText('...');
    final handoff = await actions.toBasicFlow();
    expect(handoff.draft.patientId, 'mother');
    expect(handoff.draft.type, VisitType.insurance);
    expect(
      handoff.draft.facilityId,
      isNull,
      reason: 'Sông Xanh does not take BHYT',
    );
    expect(handoff.draft.departmentId, isNull);
    expect(handoff.draft.firstMissing, BookingStage.facility);
  });

  test('booking controller applies a hand-off atomically at payment', () async {
    final c = smartContainer(FakeGateway((_, _, _) async => reply()));
    final draft = BookingDraft(
      id: 'X',
      type: VisitType.service,
      patientId: 'self',
      facilityId: 'anbinh',
      departmentId: 'general',
      doctorMode: DoctorMode.any,
    );
    c.read(bookingHandoffProvider).pending = BookingHandoff(
      draft,
      stage: BookingStage.dateTime,
    );
    c.listen(bookingSessionProvider, (_, _) {});
    expect(c.read(bookingSessionProvider).stage, BookingStage.dateTime);
    expect(c.read(bookingSessionProvider).draft.id, 'X');
    expect(c.read(bookingHandoffProvider).pending, isNull);
  });

  group('SilenceDetector', () {
    test('ends a turn only after speech followed by silence', () {
      final vad = SilenceDetector();
      expect(
        List.generate(30, (_) => vad.add(tone(10))).any((e) => e),
        isFalse,
      );
      for (var i = 0; i < 4; i++) {
        expect(vad.add(tone(5000)), isFalse);
      }
      final ends = List.generate(20, (_) => vad.add(tone(10)));
      expect(ends.where((e) => e).length, 1);
      expect(ends.indexOf(true), 16, reason: '1.7 s of 100 ms chunks');
    });

    test('a short pause to breathe does not end the turn', () {
      final vad = SilenceDetector();
      for (var i = 0; i < 5; i++) {
        vad.add(tone(5000));
      }
      expect(
        List.generate(10, (_) => vad.add(tone(10))).any((e) => e),
        isFalse,
      );
      vad.add(tone(5000));
      expect(
        List.generate(10, (_) => vad.add(tone(10))).any((e) => e),
        isFalse,
      );
    });
  });

  test('catalog matches the backend catalog (no silent drift)', () {
    final file = File('../backend/catalog/catalog.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final facilities = json['facilities'] as List;
    expect(
      facilities.map((f) => f['id']),
      BookingCatalog.facilities.map((f) => f.id),
    );
    for (final f in facilities) {
      final local = BookingCatalog.facility(f['id'] as String);
      expect(f['name'], local.name);
      expect(f['address'], local.address);
      expect(f['fee'], local.fee);
      expect(f['acceptsInsurance'], local.acceptsInsurance);
      expect(f['payAtHospital'], local.payAtHospital);
      expect(f['departments'], local.departments);
    }
    for (final d in json['departments'] as List) {
      final local = BookingCatalog.department(d['id'] as String);
      expect(d['name'], local.name);
      expect(d['maxAge'], local.maxAge);
    }
    for (final doc in json['doctors'] as List) {
      final local = BookingCatalog.doctors(
        doc['facilityId'] as String,
        doc['departmentId'] as String,
      ).firstWhere((d) => d.id == doc['id']);
      expect(doc['name'], local.name);
    }
    final dates = BookingCatalog.dates(today);
    expect(dates.length, json['schedule']['daysAhead']);
  });
}
