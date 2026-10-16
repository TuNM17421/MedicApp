import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_state.dart';
import '../../core/storage/local_vault.dart';
import '../booking/domain/booking_models.dart';
import '../consent/health_consent.dart';
import '../records/domain/visit_result.dart';

/// Prototype-only accounts. Nothing is sent to a server. An account stays in
/// memory and disappears when the app closes, unless its holder agreed to
/// keep its health data on this device ([consent]); then it is saved in the
/// encrypted vault.
class MockAccount {
  const MockAccount({
    required this.phone,
    required this.password,
    this.profiles = const [],
    this.consent,
    this.appointments = const [],
    this.results = const [],
  });
  final String phone;
  final String password;
  final List<PreviewProfile> profiles;
  final HealthConsent? consent;

  /// Newest first, as the appointments list shows them.
  final List<AppointmentRecord> appointments;

  /// Visit results and prescriptions sent by the doctor's system.
  final List<VisitResult> results;

  MockAccount copyWith({
    List<PreviewProfile>? profiles,
    HealthConsent? Function()? consent,
    List<AppointmentRecord>? appointments,
    List<VisitResult>? results,
  }) => MockAccount(
    phone: phone,
    password: password,
    profiles: profiles ?? this.profiles,
    consent: consent == null ? this.consent : consent(),
    appointments: appointments ?? this.appointments,
    results: results ?? this.results,
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

  /// `phone` or `password` when the message belongs under one field.
  final String? field;
}

/// The signed-in phone number, or null when signed out.
final authSessionProvider = NotifierProvider<AuthController, String?>(
  AuthController.new,
);

class AuthController extends Notifier<String?> {
  /// Restores the session saved with a consented account, so its holder does
  /// not have to sign in again after reopening the app.
  @override
  String? build() {
    final phone = VaultSnapshot.session(ref.read(vaultSnapshotProvider));
    return ref.read(mockAccountStoreProvider).containsKey(phone) ? phone : null;
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
