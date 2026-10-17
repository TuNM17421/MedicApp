import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medic_core/medic_core.dart';

import '../../app/state/app_state.dart';
import '../../core/storage/local_vault.dart';
import '../booking/domain/booking_models.dart';
import '../consent/health_consent.dart';
import '../sharing/application/sharing_providers.dart';
import '../sharing/data/patient_api.dart';
import '../sharing/domain/outbox.dart';
import '../sharing/domain/sharing_models.dart';

/// Accounts kept on the phone. Offline (no API_BASE_URL) they are
/// prototype-only, signed in with a password. With a backend the holder signs
/// in with a one-time code and [session] holds the clinic token (bước 16).
/// An account stays in memory and disappears when the app closes, unless its
/// holder agreed to keep its health data on this device ([consent]); then it
/// is saved in the encrypted vault, token and upload queue included.
class MockAccount {
  const MockAccount({
    required this.phone,
    required this.password,
    this.profiles = const [],
    this.consent,
    this.appointments = const [],
    this.results = const [],
    this.doseLog = const [],
    this.session,
    this.serverAppointments = const [],
    this.intake = const {},
    this.outbox = const [],
  });
  final String phone;
  final String password;
  final List<PreviewProfile> profiles;
  final HealthConsent? consent;

  /// Newest first, as the appointments list shows them.
  final List<AppointmentRecord> appointments;

  /// Visit results and prescriptions sent by the doctor's system.
  final List<VisitResult> results;

  /// Doses marked taken or skipped, oldest first.
  final List<DoseLogEntry> doseLog;

  /// Clinic sign-in, null when signed in offline or signed out.
  final PatientSession? session;

  /// Appointments the clinic holds for this phone, as last fetched.
  final List<ServerAppointment> serverAppointments;

  /// Answers to the questions before a visit, by visit id.
  final Map<String, List<IntakeAnswer>> intake;

  /// Uploads waiting for the network, oldest first.
  final List<OutboxItem> outbox;

  MockAccount copyWith({
    List<PreviewProfile>? profiles,
    HealthConsent? Function()? consent,
    List<AppointmentRecord>? appointments,
    List<VisitResult>? results,
    List<DoseLogEntry>? doseLog,
    PatientSession? Function()? session,
    List<ServerAppointment>? serverAppointments,
    Map<String, List<IntakeAnswer>>? intake,
    List<OutboxItem>? outbox,
  }) => MockAccount(
    phone: phone,
    password: password,
    profiles: profiles ?? this.profiles,
    consent: consent == null ? this.consent : consent(),
    appointments: appointments ?? this.appointments,
    results: results ?? this.results,
    doseLog: doseLog ?? this.doseLog,
    session: session == null ? this.session : session(),
    serverAppointments: serverAppointments ?? this.serverAppointments,
    intake: intake ?? this.intake,
    outbox: outbox ?? this.outbox,
  );

  MockAccount withProfiles(List<PreviewProfile> value) =>
      copyWith(profiles: value);

  MockAccount withConsent(HealthConsent? value) =>
      copyWith(consent: () => value);

  Map<String, Object?> toJson() => {
    'phone': phone,
    'password': password,
    'profiles': [for (final profile in profiles) profile.toJson()],
    'consent': consent?.toJson(),
    'appointments': [for (final record in appointments) record.toJson()],
    'results': [for (final result in results) result.toJson()],
    'doseLog': [for (final entry in doseLog) entry.toJson()],
    'session': session?.toJson(),
    'serverAppointments': [
      for (final appointment in serverAppointments) appointment.toJson(),
    ],
    'intake': {
      for (final MapEntry(:key, :value) in intake.entries)
        key: [for (final answer in value) answer.toJson()],
    },
    'outbox': [for (final item in outbox) item.toJson()],
  };

  factory MockAccount.fromJson(Map<String, Object?> json) => MockAccount(
    phone: json['phone']! as String,
    password: json['password']! as String,
    profiles: List.unmodifiable([
      for (final profile in json['profiles']! as List<Object?>)
        PreviewProfile.fromJson(profile! as Map<String, Object?>),
    ]),
    consent: switch (json['consent']) {
      final Map<String, Object?> value => HealthConsent.fromJson(value),
      _ => null,
    },
    appointments: List.unmodifiable([
      for (final record in json['appointments'] as List<Object?>? ?? const [])
        AppointmentRecord.fromJson(record! as Map<String, Object?>),
    ]),
    results: List.unmodifiable([
      for (final result in json['results'] as List<Object?>? ?? const [])
        VisitResult.fromJson(result! as Map<String, Object?>),
    ]),
    doseLog: List.unmodifiable([
      for (final entry in json['doseLog'] as List<Object?>? ?? const [])
        DoseLogEntry.fromJson(entry! as Map<String, Object?>),
    ]),
    session: switch (json['session']) {
      final Map<String, Object?> value => PatientSession.fromJson(value),
      _ => null,
    },
    serverAppointments: List.unmodifiable([
      for (final item in json['serverAppointments'] as List<Object?>? ?? [])
        ServerAppointment.fromJson(item! as Map<String, Object?>),
    ]),
    intake: Map.unmodifiable({
      for (final MapEntry(:key, :value)
          in (json['intake'] as Map<String, Object?>? ?? const {}).entries)
        key: List<IntakeAnswer>.unmodifiable([
          for (final answer in value! as List<Object?>)
            IntakeAnswer.fromJson(answer! as Map<String, Object?>),
        ]),
    }),
    outbox: List.unmodifiable([
      for (final item in json['outbox'] as List<Object?>? ?? const [])
        OutboxItem.fromJson(item! as Map<String, Object?>),
    ]),
  );
}

const demoPhone = '0912345678';
const demoPassword = '123456';

/// Accepts `0912 345 678`, `0912.345.678` and `+84912345678`.
String? normalizePhone(String input) {
  var digits = input.replaceAll(RegExp(r'[\s.\-()]'), '');
  if (digits.startsWith('+84')) digits = '0${digits.substring(3)}';
  if (digits.startsWith('84') && digits.length == 11) {
    digits = '0${digits.substring(2)}';
  }
  return RegExp(r'^0[35789]\d{8}$').hasMatch(digits) ? digits : null;
}

String formatPhone(String phone) => phone.length == 10
    ? '${phone.substring(0, 4)} ${phone.substring(4, 7)} ${phone.substring(7)}'
    : phone;

String? validatePhone(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Vui lòng nhập số điện thoại.';
  }
  return normalizePhone(value) == null
      ? 'Số điện thoại gồm 10 chữ số, bắt đầu bằng số 0.'
      : null;
}

String? validateNewPassword(String? value) =>
    value == null || value.length < 6 ? 'Mật khẩu cần ít nhất 6 ký tự.' : null;

final mockAccountStoreProvider =
    NotifierProvider<MockAccountStore, Map<String, MockAccount>>(
      MockAccountStore.new,
    );

class MockAccountStore extends Notifier<Map<String, MockAccount>> {
  @override
  Map<String, MockAccount> build() => Map.unmodifiable({
    demoPhone: const MockAccount(
      phone: demoPhone,
      password: demoPassword,
      profiles: demoProfiles,
    ),
    for (final account in VaultSnapshot.accounts(
      ref.read(vaultSnapshotProvider),
    ))
      account.phone: account,
  });

  void save(MockAccount account) =>
      state = Map.unmodifiable({...state, account.phone: account});
}

sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  const AuthSuccess();
}

class AuthFailure extends AuthResult {
  const AuthFailure(this.message, {this.field});
  final String message;

  /// `phone`, `password` or `code` when the message belongs under one field.
  final String? field;
}

/// The clinic sent a one-time code to [phone].
class OtpSent extends AuthResult {
  const OtpSent(this.phone, this.challenge);
  final String phone;
  final OtpChallenge challenge;
}

/// One-time sign-in codes are 6 digits.
const otpLength = 6;

/// The signed-in phone number, or null when signed out.
final authSessionProvider = NotifierProvider<AuthController, String?>(
  AuthController.new,
);

class AuthController extends Notifier<String?> {
  /// Restores the session saved with a consented account, so its holder does
  /// not have to sign in again after reopening the app.
  /// With a clinic backend, only an account whose clinic session is still
  /// valid stays signed in.
  @override
  String? build() {
    final phone = VaultSnapshot.session(ref.read(vaultSnapshotProvider));
    final account = ref.read(mockAccountStoreProvider)[phone];
    if (account == null) return null;
    if (ref.read(patientApiProvider) != null &&
        !(account.session?.validAt(DateTime.now()) ?? false)) {
      return null;
    }
    return phone;
  }

  /// Asks the clinic to send a sign-in code (bước 16). Returns [OtpSent] or
  /// [AuthFailure].
  Future<AuthResult> requestOtp(String phoneInput) async {
    final phone = normalizePhone(phoneInput);
    if (phone == null) {
      return AuthFailure(validatePhone(phoneInput)!, field: 'phone');
    }
    final api = ref.read(patientApiProvider);
    if (api == null) {
      return const AuthFailure('Bản thử này chưa nối với phòng khám.');
    }
    try {
      return OtpSent(phone, await api.requestOtp(phone));
    } on PatientApiException catch (failure) {
      return AuthFailure(
        failure.message,
        field: failure.code == 'bad_phone' ? 'phone' : null,
      );
    }
  }

  /// Signs in with the code the clinic sent. A phone seen for the first time
  /// gets a new account on this device.
  Future<AuthResult> verifyOtp(String phone, String code) async {
    final digits = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp('^\\d{$otpLength}\$').hasMatch(digits)) {
      return const AuthFailure('Mã gồm 6 chữ số.', field: 'code');
    }
    final api = ref.read(patientApiProvider);
    if (api == null) {
      return const AuthFailure('Bản thử này chưa nối với phòng khám.');
    }
    try {
      final session = await api.createSession(phone, digits);
      if (!ref.mounted) return const AuthSuccess();
      final store = ref.read(mockAccountStoreProvider.notifier);
      final account =
          ref.read(mockAccountStoreProvider)[phone] ??
          MockAccount(phone: phone, password: '');
      store.save(account.copyWith(session: () => session));
      state = phone;
      return const AuthSuccess();
    } on PatientApiException catch (failure) {
      return AuthFailure(
        failure.message,
        field: switch (failure.code) {
          'bad_code' => 'code',
          'bad_phone' => 'phone',
          _ => null,
        },
      );
    }
  }

  /// The clinic no longer accepts the token: sign out without asking it.
  void sessionExpired() {
    updateAccount((account) => account.copyWith(session: () => null));
    state = null;
    ref.invalidate(notificationFeedProvider);
  }

  MockAccount? get account =>
      state == null ? null : ref.read(mockAccountStoreProvider)[state];

  AuthResult signIn(String phoneInput, String password) {
    final phone = normalizePhone(phoneInput);
    if (phone == null) {
      return AuthFailure(validatePhone(phoneInput)!, field: 'phone');
    }
    final account = ref.read(mockAccountStoreProvider)[phone];
    if (account == null) {
      return const AuthFailure(
        'Chưa có tài khoản với số này. Bạn có thể tạo tài khoản mới.',
        field: 'phone',
      );
    }
    if (account.password != password) {
      return const AuthFailure('Mật khẩu chưa đúng.', field: 'password');
    }
    state = phone;
    return const AuthSuccess();
  }

  AuthResult signUp(String phoneInput, String password) {
    final phone = normalizePhone(phoneInput);
    if (phone == null) {
      return AuthFailure(validatePhone(phoneInput)!, field: 'phone');
    }
    if (ref.read(mockAccountStoreProvider).containsKey(phone)) {
      return const AuthFailure(
        'Số này đã có tài khoản. Hãy đăng nhập.',
        field: 'phone',
      );
    }
    final error = validateNewPassword(password);
    if (error != null) return AuthFailure(error, field: 'password');
    ref
        .read(mockAccountStoreProvider.notifier)
        .save(MockAccount(phone: phone, password: password));
    state = phone;
    return const AuthSuccess();
  }

  void signOut() {
    final session = account?.session;
    if (session != null) {
      final api = ref.read(patientApiProvider);
      // Best effort: the token is forgotten here whatever the network says.
      if (api != null) {
        unawaited(
          api.deleteSession(session.token).then((_) {}, onError: (_) {}),
        );
      }
      updateAccount((account) => account.copyWith(session: () => null));
    }
    state = null;
    // Another account must not see this account's notices.
    ref.invalidate(notificationFeedProvider);
  }

  void setConsent(HealthConsent? consent) {
    final current = account;
    if (current == null) return;
    ref
        .read(mockAccountStoreProvider.notifier)
        .save(current.withConsent(consent));
  }

  /// Applies [change] to the signed-in account; does nothing when signed out
  /// (tests and the design preview), so that state stays in memory only.
  void updateAccount(MockAccount Function(MockAccount) change) {
    final current = account;
    if (current == null) return;
    ref.read(mockAccountStoreProvider.notifier).save(change(current));
  }

  void saveProfiles(List<PreviewProfile> profiles) {
    final current = account;
    if (current == null) return;
    ref
        .read(mockAccountStoreProvider.notifier)
        .save(current.withProfiles(profiles));
  }
}
