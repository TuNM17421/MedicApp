import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_state.dart';

/// Prototype-only accounts kept in memory. Nothing is sent to a server or
/// written to disk, so accounts created here disappear when the app closes.
class MockAccount {
  const MockAccount({
    required this.phone,
    required this.password,
    this.profiles = const [],
  });
  final String phone;
  final String password;
  final List<PreviewProfile> profiles;

  MockAccount withProfiles(List<PreviewProfile> value) =>
      MockAccount(phone: phone, password: password, profiles: value);
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
  Map<String, MockAccount> build() => {
    demoPhone: const MockAccount(
      phone: demoPhone,
      password: demoPassword,
      profiles: demoProfiles,
    ),
  };

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
  @override
  String? build() => null;

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

  void saveProfiles(List<PreviewProfile> profiles) {
    final current = account;
    if (current == null) return;
    ref
        .read(mockAccountStoreProvider.notifier)
        .save(current.withProfiles(profiles));
  }
}
