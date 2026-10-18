import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/storage/local_vault.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/family/application/family_providers.dart';
import 'package:medic_app/features/family/data/family_api.dart';
import 'package:medic_app/features/family/domain/family_models.dart';
import 'package:medic_app/features/meds/application/meds_providers.dart';
import 'package:medic_app/features/records/application/records_providers.dart';
import 'package:medic_app/features/visit_prep/visit_prep.dart';
import 'package:medic_core/medic_core.dart';

import '../visit_prep/visit_prep_test.dart' show receipt, visit;

/// One link's mailbox, standing in for the local backend.
class FakeFamilyServer implements FamilyApi {
  final toOwner = <FamilyEvent>[];
  final toMember = <FamilyEvent>[];
  var status = FamilyLinkStatus.pending;
  var seq = 0;
  bool shareMissed = true;
  List<Map<String, Object?>> doses = const [], marks = const [];
  Map<String, Object?> profile = const {};
  String ownerName = '';

  static const code = 'ABCD-EF23';

  bool _isOwner(String token) => token == 'owner-token';

  void send(
    List<FamilyEvent> box,
    String kind,
    String id, [
    Map<String, Object?> body = const {},
  ]) => box.add(FamilyEvent(seq: ++seq, kind: kind, id: id, body: body));

  FamilyLinkInfo get _info => FamilyLinkInfo(
    id: 'L1',
    status: status,
    ownerName: ownerName,
    memberName: status == FamilyLinkStatus.pending ? null : 'Phạm Thị Lan',
    shareMissed: shareMissed,
  );

  FamilyInvite get _invite =>
      FamilyInvite(code: code, expiresAt: DateTime(2026, 10, 14, 8, 35));

  @override
  Future<({FamilyLinkInfo link, String token, FamilyInvite invite})> create({
    required String ownerName,
    required Map<String, Object?> profile,
  }) async {
    this.ownerName = ownerName;
    this.profile = profile;
    return (link: _info, token: 'owner-token', invite: _invite);
  }

  @override
  Future<FamilyInvite> reinvite(String id, String token) async => _invite;

  @override
  Future<FamilyInviter> peek(String code) async => FamilyInviter(
    ownerName: ownerName,
    relationship: profile['relationship']! as String,
  );

  @override
  Future<({FamilyLinkInfo link, String token})> claim({
    required String code,
    required String memberName,
    required bool shareMissed,
  }) async {
    if (code != FakeFamilyServer.code || status != FamilyLinkStatus.pending) {
      throw const FamilyApiException('bad_code', 'Mã chưa đúng');
    }
    status = FamilyLinkStatus.linked;
    this.shareMissed = shareMissed;
    send(toOwner, 'link.claimed', 'L1', {'memberName': memberName});
    return (link: _info, token: 'member-token');
  }

  @override
  Future<FamilyLinkInfo> view(String id, String token) async => _info;

  @override
  Future<void> end(String id, String token) async {
    status = FamilyLinkStatus.ended;
    send(_isOwner(token) ? toMember : toOwner, 'link.ended', 'L1');
  }

  @override
  Future<void> setShareMissed(String id, String token, bool value) async =>
      shareMissed = value;

  @override
  Future<void> post(
    String id,
    String token,
    List<Map<String, Object?>> events,
  ) async {
    for (final event in events) {
      send(
        _isOwner(token) ? toMember : toOwner,
        event['kind']! as String,
        event['id']! as String,
        (event['body'] as Map<String, Object?>?) ?? const {},
      );
    }
  }

  @override
  Future<FamilyFeed> read(String id, String token, {int after = 0}) async {
    final box = _isOwner(token) ? toOwner : toMember;
    return FamilyFeed(
      status: status,
      cursor: seq,
      events: [
        for (final e in box)
          if (e.seq > after) e,
      ],
    );
  }

  @override
  Future<void> putDoses(
    String id,
    String token, {
    required List<Map<String, Object?>> doses,
    required List<Map<String, Object?>> marks,
  }) async {
    this.doses = doses;
    this.marks = marks;
  }
}

class FakeAlerts implements FamilyAlertNotifier {
  final shown = <String>[];

  @override
  Future<void> show(FamilyLink link, FamilyAlert alert, String who) async =>
      shown.add('${familyAlertTitle(alert, who)} | ${familyAlertBody(alert)}');
}

const _allopurinol = PrescriptionItem(
  name: 'Allopurinol',
  strength: '300mg',
  form: 'viên',
  quantity: 10,
  doses: [Dose(DoseSlot.morning, 1)],
  meal: MealTiming.after,
  days: 10,
);

const _metformin = PrescriptionItem(
  name: 'Metformin',
  strength: '500mg',
  form: 'viên',
  quantity: 20,
  doses: [Dose(DoseSlot.morning, 1), Dose(DoseSlot.evening, 1)],
  days: 10,
);

VisitResult _result(String visitId, String profileId, PrescriptionItem item) =>
    VisitResult(
      visitId: visitId,
      profileId: profileId,
      issuedAt: DateTime(2026, 10, 14, 6),
      facilityName: 'Phòng khám thử',
      facilityPhone: '',
      doctorName: 'BS. Thử',
      patientName: 'Người thử',
      patientAge: 70,
      patientGender: 'Nữ',
      diagnosis: 'Thử',
      items: [item],
      advice: const [],
    );

const _lan = PreviewProfile(
  id: 'lan-self',
  name: 'Phạm Thị Lan',
  birthYear: 1948,
  relationship: 'Bản thân',
  gender: 'Nữ',
);

void main() {
  late FakeFamilyServer server;
  late FakeAlerts alerts;
  var now = DateTime(2026, 10, 14, 7, 10);

  ProviderContainer phone() {
    final c = ProviderContainer(
      overrides: [
        localVaultProvider.overrideWithValue(MemoryVault()),
        prepClockProvider.overrideWithValue(() => now),
        familyApiProvider.overrideWithValue(server),
        familyAlertNotifierProvider.overrideWithValue(alerts),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    server = FakeFamilyServer();
    alerts = FakeAlerts();
    now = DateTime(2026, 10, 14, 7, 10);
  });

  /// The son's phone, with his own and his mother's prescriptions.
  ProviderContainer sonPhone() {
    final c = phone();
    final auth = c.read(authSessionProvider.notifier);
    auth.signIn(demoPhone, demoPassword);
    auth.updateAccount(
      (a) => a.copyWith(
        appointments: const [],
        results: [
          _result('V-self', 'self', _metformin),
          _result('V-mother', 'mother', _allopurinol),
        ],
      ),
    );
    c.invalidate(visitResultsProvider);
    return c;
  }

  /// Mẹ Lan's own phone, freshly set up.
  ProviderContainer motherPhone() {
    final c = phone();
    final auth = c.read(authSessionProvider.notifier);
    auth.signUp('0987654321', '123456');
    auth.updateAccount((a) => a.copyWith(profiles: const [_lan]));
    return c;
  }

  test('QR codes are read whether scanned or typed', () {
    expect(inviteCodeFrom(familyQr('ABCD-EF23')), 'ABCD-EF23');
    expect(inviteCodeFrom(' abcd ef23 '), 'ABCD-EF23');
    expect(inviteCodeFrom('ABCD-EF2'), isNull);
    expect(inviteCodeFrom('https://example.com'), isNull);
  });

  test('a link survives the account JSON', () {
    const link = FamilyLink(
      id: 'L1',
      token: 't',
      role: FamilyRole.owner,
      profileId: 'mother',
      status: FamilyLinkStatus.linked,
      pushed: {'a:V1': 'f'},
    );
    final withAlert = link.copyWith(
      alerts: [
        FamilyAlert(
          kind: FamilyAlertKind.skipped,
          key: 'k',
          at: DateTime(2026, 10, 14, 7),
          label: '07:00',
          meds: const ['Allopurinol 300mg'],
          reason: 'unwell',
        ),
      ],
    );
    final copy = FamilyLink.fromJson(withAlert.toJson());
    expect(copy.pushed, {'a:V1': 'f'});
    expect(copy.alerts.single.reason, 'unwell');
    expect(copy.alerts.single.at, DateTime(2026, 10, 14, 7));
  });

  test('linking moves Mẹ Lan\'s medicines to her phone; appointments go '
      'both ways; the son hears only of her missed doses', () async {
    final son = sonPhone();
    final mother = motherPhone();
    final sonFamily = son.read(familyControllerProvider.notifier);
    final motherFamily = mother.read(familyControllerProvider.notifier);

    // Before linking, the son's phone reminds both prescriptions.
    expect(
      son.read(medicationCoursesProvider).map((c) => c.profileId).toSet(),
      {'self', 'mother'},
    );

    final pending = await sonFamily.invite('mother');
    expect(pending.inviteCode, FakeFamilyServer.code);
    expect(server.profile['relationship'], 'Mẹ');
    expect(server.ownerName, 'Phạm Văn Hòa');
    // Still pending: reminders stay on the son's phone.
    expect(son.read(medsOnOtherPhoneProvider), isEmpty);

    final inviter = await motherFamily.peek(FakeFamilyServer.code);
    expect(inviter.ownerName, 'Phạm Văn Hòa');
    final joined = await motherFamily.join(
      FakeFamilyServer.code,
      shareMissed: true,
    );
    expect(joined.role, FamilyRole.member);
    expect(joined.profileId, 'lan-self');
    expect(joined.peerName, 'Phạm Văn Hòa');

    // The son's phone learns of the claim and forwards her prescription and
    // appointment; his own medicines stay on his phone.
    son
        .read(authSessionProvider.notifier)
        .updateAccount(
          (a) => a.copyWith(
            appointments: [
              AppointmentRecord(
                visit(id: 'A-mother', patientId: 'mother'),
                receipt,
              ),
              AppointmentRecord(visit(id: 'A-self'), receipt),
            ],
          ),
        );
    await sonFamily.sync();
    final sonLink = son.read(familyLinksProvider).single;
    expect(sonLink.linked, isTrue);
    expect(sonLink.peerName, 'Phạm Thị Lan');
    expect(son.read(medsOnOtherPhoneProvider), {'mother'});
    expect(
      son.read(medicationCoursesProvider).map((c) => c.profileId).toSet(),
      {'self'},
    );
    expect(server.toMember.map((e) => (e.kind, e.id)), [
      ('appointment.upsert', 'A-mother'),
      ('result.upsert', 'V-mother'),
    ]);

    await motherFamily.sync();
    final motherAccount = mother.read(authSessionProvider.notifier).account!;
    expect(motherAccount.appointments.single.visit.patientId, 'lan-self');
    expect(motherAccount.appointments.single.visit.patientName, 'Phạm Thị Lan');
    expect(mother.read(medicationCoursesProvider).map((c) => c.item.name), [
      'Allopurinol',
    ]);
    // Her schedule went up, with only the medicine titles.
    expect(server.doses.first['label'], '07:00');
    expect(server.doses.first['meds'], ['Allopurinol 300mg']);
    expect(server.marks, isEmpty);

    // What she received is not echoed back; a booking of her own goes to
    // the son.
    final before = server.toOwner.length;
    await motherFamily.sync();
    expect(server.toOwner, hasLength(before));
    mother
        .read(authSessionProvider.notifier)
        .updateAccount(
          (a) => a.copyWith(
            appointments: [
              ...a.appointments,
              AppointmentRecord(
                visit(id: 'A-own', patientId: 'lan-self'),
                receipt,
              ),
            ],
          ),
        );
    await motherFamily.sync();
    expect(server.toOwner.last.id, 'A-own');
    await sonFamily.sync();
    final sonAppointments = son
        .read(authSessionProvider.notifier)
        .account!
        .appointments;
    expect(
      sonAppointments.firstWhere((r) => r.visit.id == 'A-own').visit.patientId,
      'mother',
    );
    expect(server.toMember.where((e) => e.id == 'A-own'), isEmpty);

    // The server says a dose was missed; the son is told once.
    server.send(server.toOwner, 'dose.missed', 'k1', {
      'at': '2026-10-14T07:00:00+07:00',
      'label': '07:00',
      'meds': ['Allopurinol 300mg'],
    });
    await sonFamily.sync();
    await sonFamily.sync();
    expect(alerts.shown, [
      'Mẹ Lan chưa uống thuốc 07:00 | Allopurinol 300mg. Bạn có thể gọi hỏi thăm.',
    ]);
    final alert = son.read(familyLinksProvider).single.alerts.single;
    expect(alert.at, DateTime(2026, 10, 14, 7));

    // She ends the link: reminders come back to the son's phone.
    await motherFamily.unlink(mother.read(familyLinksProvider).single);
    await sonFamily.sync();
    expect(son.read(familyLinksProvider).single.status, FamilyLinkStatus.ended);
    expect(son.read(medsOnOtherPhoneProvider), isEmpty);
    expect(
      son.read(medicationCoursesProvider).map((c) => c.profileId).toSet(),
      {'self', 'mother'},
    );
  });

  test('member marks go up, and nothing when sharing is off', () async {
    final mother = motherPhone();
    mother
        .read(authSessionProvider.notifier)
        .updateAccount(
          (a) => a.copyWith(
            results: [_result('V-mother', 'lan-self', _allopurinol)],
          ),
        );
    final family = mother.read(familyControllerProvider.notifier);
    await (sonPhone().read(familyControllerProvider.notifier)).invite('mother');
    await family.join(FakeFamilyServer.code, shareMissed: false);
    expect(server.doses, isEmpty);

    mother
        .read(authSessionProvider.notifier)
        .updateAccount(
          (a) => a.copyWith(
            doseLog: [
              DoseLogEntry(
                courseId: 'V-mother#1',
                day: '2026-10-14',
                slot: DoseSlot.morning,
                mark: DoseMark.skipped,
                reason: SkipReason.unwell,
                at: DateTime(2026, 10, 14, 7, 5),
              ),
            ],
          ),
        );
    await family.setShareMissed(mother.read(familyLinksProvider).single, true);
    // Turning sharing on syncs straight away.
    while (mother.read(familyControllerProvider)) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(server.shareMissed, isTrue);
    expect(server.marks, [
      {
        'key': '2026-10-14|morning',
        'mark': 'skipped',
        'reason': 'unwell',
        'at': '2026-10-14T07:05:00+07:00',
      },
    ]);
  });
}
