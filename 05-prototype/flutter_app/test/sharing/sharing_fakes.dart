import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/storage/local_vault.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/consent/health_consent.dart';
import 'package:medic_app/features/sharing/application/sharing_providers.dart';
import 'package:medic_app/features/sharing/data/patient_api.dart';
import 'package:medic_app/features/sharing/domain/sharing_models.dart';
import 'package:medic_app/features/visit_prep/visit_prep.dart';
import 'package:medic_core/medic_core.dart';

const lanPhone = '0912000482';

/// 2026-10-16 09:00 in Vietnam.
final now = DateTime.utc(2026, 10, 16, 2);

SharingConsent sharedConsent({
  Set<ShareScope> scope = const {ShareScope.intake, ShareScope.doseLog},
}) => SharingConsent(
  state: SharingState.shared,
  scope: scope,
  grantedAt: now,
  expiresAt: DateTime.utc(2026, 11, 15, 1, 30),
);

ServerAppointment lanVisit({
  SharingConsent? consent,
  String status = 'booked',
}) => ServerAppointment(
  id: 'a-p2',
  clinic: const ClinicRef(
    id: 'c-anbinh',
    name: 'Phòng khám Đa khoa An Bình',
    phone: '0900 000 000',
  ),
  startsAt: DateTime.utc(2026, 10, 16, 1, 30),
  time: '08:30',
  specialty: 'Nội tổng hợp',
  kind: 'Khám dịch vụ',
  status: status,
  resultStatus: 'none',
  consent: consent,
  patientName: 'Phạm Thị Lan',
);

/// A patient API that answers from memory and records what it was asked.
class FakePatientApi implements PatientApi {
  final calls = <String>[];
  final intake = <String, List<Map<String, Object?>>>{};
  final doseEvents = <Map<String, Object?>>[];
  List<ServerAppointment> appointmentsToReturn = [];

  /// Thrown by the next upload (intake, self meds or doses) when set.
  PatientApiException? uploadFailure;
  PatientApiException? consentFailure;

  @override
  Future<OtpChallenge> requestOtp(String phone) async {
    calls.add('otp $phone');
    return const OtpChallenge(expiresIn: 300, devCode: '123456');
  }

  @override
  Future<PatientSession> createSession(String phone, String code) async {
    calls.add('session $phone $code');
    if (code != '123456') {
      throw const PatientApiException('bad_code', 'Mã chưa đúng.', status: 401);
    }
    return PatientSession(
      token: 'tok',
      expiresAt: DateTime.utc(2099),
      phone: phone,
      name: 'Phạm Thị Lan',
    );
  }

  @override
  Future<void> deleteSession(String token) async => calls.add('delete $token');

  @override
  Future<List<ServerAppointment>> appointments(
    String token, {
    String fallbackName = '',
  }) async {
    calls.add('appointments');
    return appointmentsToReturn;
  }

  @override
  Future<VisitResult?> result(
    String token,
    String appointmentId, {
    required String profileId,
  }) async {
    calls.add('result $appointmentId');
    return null;
  }

  @override
  Future<SharingConsent> grantConsent(
    String token,
    String appointmentId,
    Set<ShareScope> scope,
  ) async {
    calls.add('grant $appointmentId ${scope.map((s) => s.wire).join(',')}');
    if (consentFailure case final failure?) throw failure;
    return sharedConsent(scope: scope);
  }

  @override
  Future<SharingConsent> revokeConsent(
    String token,
    String appointmentId,
  ) async {
    calls.add('revoke $appointmentId');
    if (consentFailure case final failure?) throw failure;
    return SharingConsent(
      state: SharingState.revoked,
      scope: const {ShareScope.intake},
      grantedAt: now,
      expiresAt: DateTime.utc(2026, 11, 15),
      revokedAt: now,
    );
  }

  void _upload(String call) {
    calls.add(call);
    if (uploadFailure case final failure?) throw failure;
  }

  @override
  Future<int> putIntake(
    String token,
    String appointmentId,
    List<Map<String, Object?>> answers,
  ) async {
    _upload('intake $appointmentId');
    intake[appointmentId] = answers;
    return answers.length;
  }

  @override
  Future<int> putSelfMeds(
    String token,
    String appointmentId,
    List<Map<String, Object?>> items,
  ) async {
    _upload('self-meds $appointmentId');
    return items.length;
  }

  @override
  Future<DoseUploadResult> postDoseEvents(
    String token,
    List<Map<String, Object?>> events,
  ) async {
    _upload('doses ${events.length}');
    doseEvents.addAll(events);
    return DoseUploadResult(accepted: events.length);
  }
}

/// A signed-in clinic account restored from the vault, as after a restart.
Map<String, Object?> signedInSnapshot({
  List<ServerAppointment>? appointments,
  List<VisitResult> results = const [],
}) => VaultSnapshot.encode({
  lanPhone: MockAccount(
    phone: lanPhone,
    password: '',
    profiles: [demoProfiles[1].withSelf()],
    consent: HealthConsent(version: healthConsentVersion, acceptedAt: now),
    session: PatientSession(
      token: 'tok',
      expiresAt: DateTime.utc(2099),
      phone: lanPhone,
      name: 'Phạm Thị Lan',
    ),
    serverAppointments: appointments ?? [lanVisit()],
    results: results,
  ),
}, lanPhone)!;

extension on PreviewProfile {
  PreviewProfile withSelf() => PreviewProfile(
    id: id,
    name: name,
    birthYear: birthYear,
    relationship: selfRelationship,
    gender: gender,
  );
}

List<Override> overridesFor(
  FakePatientApi api, {
  Map<String, Object?>? snapshot,
  bool signedIn = true,
}) => [
  patientApiProvider.overrideWithValue(api),
  sharingClockProvider.overrideWithValue(() => now),
  prepClockProvider.overrideWithValue(() => DateTime(2026, 10, 16, 9)),
  localVaultProvider.overrideWithValue(MemoryVault()),
  vaultSnapshotProvider.overrideWithValue(
    signedIn ? snapshot ?? signedInSnapshot() : null,
  ),
];

ProviderContainer signedInContainer(
  FakePatientApi api, {
  Map<String, Object?>? snapshot,
  List<Override> extra = const [],
}) => ProviderContainer(
  overrides: [
    ...overridesFor(api, snapshot: snapshot),
    ...extra,
  ],
);
