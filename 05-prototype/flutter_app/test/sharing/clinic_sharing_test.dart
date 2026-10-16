import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/router/app_router.dart';
import 'package:medic_app/app/router/app_routes.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/meds/application/meds_providers.dart';
import 'package:medic_app/features/meds/data/med_reminder_scheduler.dart';
import 'package:medic_app/features/sharing/application/sharing_providers.dart';
import 'package:medic_app/main.dart';

import 'sharing_fakes.dart';

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakePatientApi api, {
  bool signedIn = true,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      ...overridesFor(api, signedIn: signedIn),
      bookingTodayProvider.overrideWithValue(DateTime(2026, 10, 16)),
      pendingDoseStoreProvider.overrideWithValue(MemoryPendingDoseStore()),
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

Future<void> _tap(WidgetTester tester, String key, {double delta = 200}) async {
  final target = find.byKey(ValueKey(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) =>
    tester
        .widget<FilledButton>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed !=
    null;

bool _ticked(WidgetTester tester, String key) =>
    tester.widget<CheckboxListTile>(find.byKey(ValueKey(key))).value!;

void main() {
  testWidgets('sharing needs a choice and an unticked confirmation; '
      'withdrawing is one tap away', (tester) async {
    final api = FakePatientApi()..appointmentsToReturn = [lanVisit()];
    final c = await _open(tester, api);
    c.read(appRouterProvider).go(AppRoutes.appointment('a-p2'));
    await tester.pumpAndSettle();
    expect(find.text('Phòng khám Đa khoa An Bình'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('clinic-sharing')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Chưa chia sẻ'), findsOneWidget);

    await _tap(tester, 'clinic-sharing-open');
    expect(
      find.text('Bạn muốn cho Phòng khám Đa khoa An Bình xem những gì?'),
      findsOneWidget,
    );
    for (final key in [
      'share-scope-intake',
      'share-scope-dose_log',
      'share-scope-self_meds',
      'share-confirm',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(_ticked(tester, key), isFalse, reason: '$key is not pre-ticked');
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('share-submit')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(_enabled(tester, 'share-submit'), isFalse);
    expect(
      find.textContaining('đến hết ngày 15/11/2026', findRichText: true),
      findsOneWidget,
    );

    await _tap(tester, 'share-confirm');
    expect(
      _enabled(tester, 'share-submit'),
      isFalse,
      reason: 'nothing chosen yet',
    );
    await _tap(tester, 'share-scope-intake', delta: -200);
    await _tap(tester, 'share-scope-dose_log', delta: -200);
    await tester.scrollUntilVisible(
      find.byKey(const Key('share-submit')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(_enabled(tester, 'share-submit'), isTrue);
    expect(api.calls.where((call) => call.startsWith('grant')), isEmpty);

    await _tap(tester, 'share-submit');
    expect(api.calls, contains('grant a-p2 intake,dose_log'));
    expect(find.byKey(const Key('clinic-sharing')), findsOneWidget);
    expect(find.text('Đang chia sẻ đến 15/11'), findsOneWidget);

    // The confirmation snackbar would cover the bottom of the next page.
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await _tap(tester, 'clinic-sharing-open');
    expect(find.text('Đang chia sẻ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('share-confirm')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(_ticked(tester, 'share-confirm'), isFalse);
    await _tap(tester, 'share-withdraw');
    expect(find.textContaining('từ lần mở hồ sơ tiếp theo'), findsWidgets);
    await _tap(tester, 'share-withdraw-confirm');
    expect(api.calls, contains('revoke a-p2'));
    expect(find.byKey(const Key('share-withdraw')), findsNothing);
    expect(find.byKey(const Key('share-later')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Đã rút lại'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(_ticked(tester, 'share-scope-intake'), isFalse);
  });

  testWidgets('a cancelled appointment cannot be shared', (tester) async {
    final api = FakePatientApi()
      ..appointmentsToReturn = [lanVisit(status: 'cancelled')];
    final c = await _open(tester, api);
    c.read(appRouterProvider).go(AppRoutes.appointment('a-p2'));
    await tester.pumpAndSettle();
    expect(find.text('Đã hủy'), findsOneWidget);
    expect(find.byKey(const Key('clinic-sharing')), findsNothing);
  });

  testWidgets('sign-in with phone and the code the clinic sends', (
    tester,
  ) async {
    final api = FakePatientApi();
    final c = await _open(tester, api, signedIn: false);
    expect(find.byKey(const Key('welcome-sign-up')), findsNothing);
    await _tap(tester, 'welcome-sign-in');
    await tester.enterText(find.byKey(const Key('auth-phone')), '0912 000 482');
    await tester.tap(find.text('Gửi mã'));
    await tester.pumpAndSettle();
    expect(api.calls, ['otp $lanPhone']);
    expect(find.text('Chưa gửi tin nhắn thật. Mã thử: 123456'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-code')), '000000');
    await tester.tap(find.text('Đăng nhập').last);
    await tester.pumpAndSettle();
    expect(find.text('Mã chưa đúng.'), findsOneWidget);
    expect(c.read(authSessionProvider), isNull);

    await tester.enterText(find.byKey(const Key('otp-code')), '123456');
    await tester.tap(find.text('Đăng nhập').last);
    await tester.pumpAndSettle();
    expect(c.read(authSessionProvider), lanPhone);
    expect(c.read(patientSessionProvider)!.token, 'tok');
    // A phone seen for the first time sets up its own profile first.
    expect(find.byKey(const Key('otp-code')), findsNothing);
    expect(api.calls, contains('appointments'));
  });
}
