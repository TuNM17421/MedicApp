import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_vault.dart';
import '../auth/auth_controller.dart';

/// Version of the wording on the consent page. Bump it when the page changes
/// what is stored or why, so the record shows which text was agreed to.
const healthConsentVersion = '2026-10-15';

/// The account holder's agreement to keep their family's health data on this
/// device. Health data is sensitive personal data under Nghị định
/// 356/2025/NĐ-CP, so it needs an explicit, recorded, withdrawable consent.
@immutable
class HealthConsent {
  const HealthConsent({required this.version, required this.acceptedAt});
  final String version;
  final DateTime acceptedAt;

  Map<String, Object?> toJson() => {
    'version': version,
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
  };

  factory HealthConsent.fromJson(Map<String, Object?> json) => HealthConsent(
    version: json['version']! as String,
    acceptedAt: DateTime.parse(json['acceptedAt']! as String).toLocal(),
  );
}

/// Shape of the vault document. Only consented accounts are written, and the
/// session only when it belongs to one of them.
abstract final class VaultSnapshot {
  static const _version = 1;

  static Map<String, Object?>? encode(
    Map<String, MockAccount> accounts,
    String? session,
  ) {
    final kept = [
      for (final account in accounts.values)
        if (account.consent != null) account,
    ];
    if (kept.isEmpty) return null;
    return {
      'v': _version,
      'accounts': [for (final account in kept) account.toJson()],
      'session': kept.any((account) => account.phone == session)
          ? session
          : null,
    };
  }

  static List<MockAccount> accounts(Map<String, Object?>? data) {
    if (data == null || data['v'] != _version) return const [];
    try {
      return [
        for (final account in data['accounts']! as List<Object?>)
          MockAccount.fromJson(account! as Map<String, Object?>),
      ];
    } on Object {
      return const [];
    }
  }

  static String? session(Map<String, Object?>? data) =>
      data?['v'] == _version ? data!['session'] as String? : null;
}

/// Writes consented accounts to the vault whenever they change, and empties
/// the vault once no account has consent. Watched by the app root.
final vaultSyncProvider = Provider<void>((ref) {
  final vault = ref.watch(localVaultProvider);
  var pending = Future<void>.value();
  void save() {
    final data = VaultSnapshot.encode(
      ref.read(mockAccountStoreProvider),
      ref.read(authSessionProvider),
    );
    pending = pending
        .then((_) => data == null ? vault.wipe() : vault.write(data))
        .onError((error, _) => debugPrint('Vault write failed: $error'));
  }

  ref.listen(mockAccountStoreProvider, (_, _) => save());
  ref.listen(authSessionProvider, (_, _) => save());
});

/// The signed-in account's consent, or null when it has not agreed.
final healthConsentProvider = Provider<HealthConsent?>((ref) {
  final phone = ref.watch(authSessionProvider);
  return ref.watch(mockAccountStoreProvider)[phone]?.consent;
});

/// "Để sau" on the home prompt hides it until the app restarts.
final consentPromptDismissedProvider =
    NotifierProvider<ConsentPromptDismissed, bool>(ConsentPromptDismissed.new);

class ConsentPromptDismissed extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(authSessionProvider);
    return false;
  }

  void dismiss() => state = true;
}
