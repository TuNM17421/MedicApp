import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/storage/local_vault.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/consent/health_consent.dart';
import 'package:medic_app/main.dart';

final _consent = HealthConsent(
  version: healthConsentVersion,
  acceptedAt: DateTime.utc(2026, 10, 15, 3),
);

Future<ProviderContainer> _open(WidgetTester tester, MemoryVault vault) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      bookingTodayProvider.overrideWithValue(DateTime(2026, 10, 14)),
      localVaultProvider.overrideWithValue(vault),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MedicApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('VaultSnapshot', () {
    test('keeps only consented accounts and their session', () {
      final accounts = {
        demoPhone: const MockAccount(
          phone: demoPhone,
          password: demoPassword,
          profiles: demoProfiles,
        ),
        '0987654321': MockAccount(
          phone: '0987654321',
          password: '123456',
          profiles: [
            demoProfiles[1].withConditions(['gout']),
          ],
          consent: _consent,
        ),
      };
      expect(VaultSnapshot.encode(accounts, demoPhone)!['session'], isNull);

      final data = VaultSnapshot.encode(accounts, '0987654321')!;
      final json = jsonDecode(jsonEncode(data)) as Map<String, Object?>;
      final restored = VaultSnapshot.accounts(json);
      expect(restored.map((a) => a.phone), ['0987654321']);
      expect(restored.single.profiles.single.conditions, ['gout']);
      expect(restored.single.consent!.version, healthConsentVersion);
      expect(VaultSnapshot.session(json), '0987654321');

      expect(
        VaultSnapshot.encode({demoPhone: accounts[demoPhone]!}, null),
        isNull,
      );
      expect(VaultSnapshot.accounts({'v': 99}), isEmpty);
    });

    test('restores the saved account and session at startup', () {
      final snapshot = VaultSnapshot.encode({
        '0987654321': MockAccount(
          phone: '0987654321',
          password: '123456',
          profiles: [demoProfiles.first],
          consent: _consent,
        ),
      }, '0987654321');
      final c = ProviderContainer(
        overrides: [vaultSnapshotProvider.overrideWithValue(snapshot)],
      );
      addTearDown(c.dispose);
      expect(c.read(authSessionProvider), '0987654321');
      expect(c.read(profileCatalogProvider).single.name, 'Phạm Văn Hòa');
      expect(c.read(healthConsentProvider), isNotNull);
      expect(c.read(mockAccountStoreProvider), contains(demoPhone));
    });
  });

  group('EncryptedFileVault', () {
    late Directory dir;
    late EncryptedFileVault vault;
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('vault');
      vault = EncryptedFileVault(file: () async => File('${dir.path}/v.bin'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips without leaving readable text on disk', () async {
      expect(await vault.read(), isNull);
      await vault.write({'name': 'Phạm Thị Lan', 'idNumber': '001148000000'});
      final raw = File('${dir.path}/v.bin').readAsBytesSync();
      expect(latin1.decode(raw, allowInvalid: true), isNot(contains('001148')));
      expect((await vault.read())!['name'], 'Phạm Thị Lan');

      await vault.wipe();
      expect(File('${dir.path}/v.bin').existsSync(), isFalse);
      expect(await vault.read(), isNull);
    });

    test('drops a file whose key is gone', () async {
      await vault.write({'a': 1});
      FlutterSecureStorage.setMockInitialValues({});
      expect(await vault.read(), isNull);
      expect(File('${dir.path}/v.bin').existsSync(), isFalse);
    });
  });

  testWidgets('agreeing saves the account; withdrawing empties the vault', (
    tester,
  ) async {
    final vault = MemoryVault();
    final c = await _open(tester, vault);
    c.read(authSessionProvider.notifier).signIn(demoPhone, demoPassword);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('consent-prompt')), findsOneWidget);
    expect(await vault.read(), isNull);

    await _tap(tester, 'consent-prompt-open');
    expect(find.text('Lưu dữ liệu sức khỏe'), findsOneWidget);
    final accept = find.byKey(const Key('consent-accept'));
    await tester.scrollUntilVisible(
      accept,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: accept, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'consent-understood');
    await _tap(tester, 'consent-accept');

    expect(find.byKey(const Key('consent-prompt')), findsNothing);
    final saved = await vault.read();
    expect(VaultSnapshot.accounts(saved).single.phone, demoPhone);
    expect(VaultSnapshot.session(saved), demoPhone);

    await _tap(tester, 'nav-Tài khoản');
    expect(find.textContaining('Đang lưu trên máy này'), findsOneWidget);
    await _tap(tester, 'account-consent-withdraw');
    await tester.tap(find.text('Ngừng lưu'));
    await tester.pumpAndSettle();
    expect(await vault.read(), isNull);
    expect(find.textContaining('Chưa lưu trên máy này'), findsOneWidget);
  });

  testWidgets('"Để sau" hides the prompt without saving', (tester) async {
    final vault = MemoryVault();
    final c = await _open(tester, vault);
    c.read(authSessionProvider.notifier).signIn(demoPhone, demoPassword);
    await tester.pumpAndSettle();
    await _tap(tester, 'consent-prompt-later');
    expect(find.byKey(const Key('consent-prompt')), findsNothing);
    expect(await vault.read(), isNull);
  });
}
