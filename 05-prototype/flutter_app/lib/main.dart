import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/storage/local_vault.dart';
import 'features/consent/health_consent.dart';
import 'features/meds/application/meds_providers.dart';
import 'features/sharing/application/sharing_providers.dart';
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

class MedicApp extends ConsumerStatefulWidget {
  const MedicApp({super.key, this.builder});
  final TransitionBuilder? builder;

  @override
  ConsumerState<MedicApp> createState() => _MedicAppState();
}

class _MedicAppState extends ConsumerState<MedicApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      if (!mounted) return;
      ref.read(doseLogProvider.notifier).refresh();
      ref.read(serverAppointmentsProvider.notifier).sync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(doseLogProvider.notifier).refresh();
      ref.read(serverAppointmentsProvider.notifier).sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reminderSyncProvider);
    ref.watch(medReminderSyncProvider);
    ref.watch(vaultSyncProvider);
    ref.watch(clinicSyncProvider);
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
    builder: widget.builder,
  );
}
