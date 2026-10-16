import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/storage/local_vault.dart';
import 'features/consent/health_consent.dart';
import 'features/visit_prep/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Be Vietnam Pro',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final vault = EncryptedFileVault();
  final snapshot = await vault.read();
  runApp(
    ProviderScope(
      overrides: [
        localVaultProvider.overrideWithValue(vault),
        vaultSnapshotProvider.overrideWithValue(snapshot),
      ],
      child: const MedicApp(),
    ),
  );
}

class MedicApp extends ConsumerWidget {
  const MedicApp({super.key, this.builder});
  final TransitionBuilder? builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(reminderSyncProvider);
    ref.watch(vaultSyncProvider);
    return _app(ref);
  }

  Widget _app(WidgetRef ref) => MaterialApp.router(
    title: 'MedicApp',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: ref.watch(appRouterProvider),
    builder: builder,
  );
}
