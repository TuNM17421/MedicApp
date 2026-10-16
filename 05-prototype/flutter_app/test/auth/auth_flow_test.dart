import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/router/app_router.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/widgets/app_primitives.dart';
import 'package:medic_app/features/auth/auth_controller.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/profiles/cccd_scanner.dart';
import 'package:medic_app/main.dart';

import 'auth_fakes.dart';

/// Opens the real app with the production router, starting signed out.
Future<ProviderContainer> openSignedOut(
  WidgetTester tester, {
  FakeScanner? scanner,
  double scale = 1,
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      bookingTodayProvider.overrideWithValue(DateTime(2026, 10, 14)),
      cccdScannerProvider.overrideWithValue(scanner ?? FakeScanner()),
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapFound(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) =>
    tapFound(tester, find.byKey(ValueKey(key)));

Future<void> pressAction(WidgetTester tester) =>
    tapFound(tester, find.byType(AppPrimaryButton));

String location(ProviderContainer c) => c
    .read(appRouterProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

void main() {
  group('authRedirect', () {
    test('signed out users only reach the sign-in pages', () {
      expect(
        authRedirect('/home', signedIn: false, hasProfile: false),
        '/welcome',
      );
      expect(
        authRedirect('/sign-up', signedIn: false, hasProfile: false),
        isNull,
      );
      expect(
        authRedirect(
          '/profile-new?for=self',
          signedIn: false,
          hasProfile: false,
        ),
        '/welcome',
      );
    });

    test('a new account must create its own profile first', () {
      expect(
        authRedirect('/home', signedIn: true, hasProfile: false),
        '/profile-new?for=self',
      );
      expect(
        authRedirect(
          '/profile-new/scan?for=self',
          signedIn: true,
          hasProfile: false,
        ),
        isNull,
      );
    });

    test('signed in users leave the sign-in pages', () {
      expect(
        authRedirect('/sign-in', signedIn: true, hasProfile: true),
        '/home',
      );
      expect(
        authRedirect('/booking', signedIn: true, hasProfile: true),
        isNull,
      );
    });
  });

  test('sign-up and sign-in validate in plain words', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final auth = c.read(authSessionProvider.notifier);
    expect(normalizePhone('+84 912 345 678'), '0912345678');
    expect(normalizePhone('0212345678'), isNull);
    expect(
      (auth.signUp(demoPhone, '123456') as AuthFailure).message,
      contains('đã có tài khoản'),
    );
    expect((auth.signUp('0987654321', '123') as AuthFailure).field, 'password');
    expect(
      (auth.signIn('0987654321', '123456') as AuthFailure).message,
      contains('Chưa có tài khoản'),
    );
    expect((auth.signIn(demoPhone, 'sai') as AuthFailure).field, 'password');
    expect(c.read(authSessionProvider), isNull);
    expect(auth.signIn('0912 345 678', demoPassword), isA<AuthSuccess>());
    expect(c.read(profileCatalogProvider).first.name, 'Phạm Văn Hòa');
  });

  testWidgets(
    'sign up, scan own CCCD, check, save, then sign out and back in',
    (tester) async {
      final scanner = FakeScanner();
      final c = await openSignedOut(tester, scanner: scanner);
      expect(location(c), '/welcome');
      expect(find.text('Chào mừng bạn'), findsOneWidget);

      await tapKey(tester, 'welcome-sign-up');
      expect(find.text('Bước 1/2 · Tạo tài khoản'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('auth-phone')),
        '0912 345 678',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sign-up-password')),
          matching: find.byType(EditableText),
        ),
        'matkhau1',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sign-up-confirm')),
          matching: find.byType(EditableText),
        ),
        'matkhau2',
      );
      await pressAction(tester);
      expect(find.text('Hai mật khẩu chưa giống nhau.'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sign-up-confirm')),
          matching: find.byType(EditableText),
        ),
        'matkhau1',
      );
      await pressAction(tester);
      expect(
        find.text('Số này đã có tài khoản. Hãy đăng nhập.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('auth-phone')),
        '0987 654 321',
      );
      await pressAction(tester);
      expect(location(c), '/profile-new?for=self');
      expect(find.text('Bước 2/2 · Hồ sơ của bạn'), findsOneWidget);

      await tapKey(tester, 'add-profile-scan');
      expect(find.byKey(const Key('fake-camera')), findsOneWidget);
      scanner.emit('https://example.com/not-a-card');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cccd-scan-error')), findsOneWidget);

      scanner.emit(sampleCccdQr);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-form-from-cccd')), findsOneWidget);
      expect(find.text('079••••••234'), findsOneWidget);
      expect(find.text('Trần Thị Mai'), findsOneWidget);
      expect(find.text('15/03/1965'), findsOneWidget);

      await pressAction(tester);
      expect(location(c), '/home');
      expect(find.text('Xin chào,\nTrần Thị Mai'), findsOneWidget);
      final profiles = c.read(profileCatalogProvider);
      expect(profiles, hasLength(1));
      expect(profiles.single.relationship, 'Bản thân');
      expect(profiles.single.gender, 'Nữ');
      expect(profiles.single.idNumber, '079065001234');

      await tapFound(tester, find.byKey(const ValueKey('nav-Tài khoản')));
      expect(find.text('0987 654 321'), findsOneWidget);
      await tapKey(tester, 'account-sign-out');
      await tapFound(tester, find.widgetWithText(FilledButton, 'Đăng xuất'));
      expect(location(c), '/welcome');

      await tapKey(tester, 'welcome-sign-in');
      await tester.enterText(find.byKey(const Key('auth-phone')), '0987654321');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sign-in-password')),
          matching: find.byType(EditableText),
        ),
        'matkhau1',
      );
      await pressAction(tester);
      expect(location(c), '/home');
      expect(find.text('Xin chào,\nTrần Thị Mai'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('demo sign-in shows the demo family; a wrong password does not', (
    tester,
  ) async {
    final c = await openSignedOut(tester);
    await tapKey(tester, 'welcome-sign-in');
    await tester.enterText(find.byKey(const Key('auth-phone')), demoPhone);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('sign-in-password')),
        matching: find.byType(EditableText),
      ),
      'sai-mat-khau',
    );
    await pressAction(tester);
    expect(find.text('Mật khẩu chưa đúng.'), findsOneWidget);
    expect(find.byKey(const Key('sign-in-demo')), findsOneWidget);

    await tapKey(tester, 'sign-in-demo');
    await pressAction(tester);
    expect(location(c), '/home');
    expect(find.text('Xin chào,\nPhạm Văn Hòa'), findsOneWidget);
  });

  testWidgets('add a relative from a photo of their CCCD', (tester) async {
    final scanner = FakeScanner();
    final c = await openSignedOut(tester, scanner: scanner);
    c.read(authSessionProvider.notifier).signIn(demoPhone, demoPassword);
    await tester.pumpAndSettle();
    await tapFound(tester, find.byKey(const ValueKey('nav-Hồ sơ')));
    await tapKey(tester, 'profiles-add');
    expect(find.text('Tạo hồ sơ cho người thân'), findsOneWidget);
    await tapKey(tester, 'add-profile-scan');

    scanner.image = () async => throw const NoQrInImageException();
    await tapKey(tester, 'cccd-pick-image');
    expect(find.textContaining('Không thấy mã QR trong ảnh'), findsOneWidget);

    scanner.image = () async => sampleCccdQr;
    await tapKey(tester, 'cccd-pick-image');
    expect(find.text('Trần Thị Mai'), findsOneWidget);

    await pressAction(tester);
    expect(find.text('Vui lòng chọn quan hệ.'), findsOneWidget);
    await tapKey(tester, 'choice-Mẹ');
    await pressAction(tester);
    expect(location(c), '/profiles');
    expect(find.text('Trần Thị Mai'), findsOneWidget);
    expect(c.read(profileCatalogProvider), hasLength(4));
    expect(c.read(profileCatalogProvider).first.name, 'Phạm Văn Hòa');
  });

  testWidgets('manual entry checks required fields', (tester) async {
    final c = await openSignedOut(tester);
    c.read(authSessionProvider.notifier).signUp('0987654321', '123456');
    await tester.pumpAndSettle();
    await tapKey(tester, 'add-profile-manual');
    await pressAction(tester);
    expect(find.text('Vui lòng nhập họ và tên.'), findsOneWidget);
    expect(find.text('Vui lòng chọn giới tính.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profile-form-name')),
      'Ngô Văn Tư',
    );
    await tester.enterText(
      find.byKey(const Key('profile-form-birth')),
      '31/02/1960',
    );
    await pressAction(tester);
    expect(find.textContaining('Nhập ngày sinh theo dạng'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profile-form-birth')),
      '1/2/1960',
    );
    await tapKey(tester, 'choice-Nam');
    await pressAction(tester);
    expect(location(c), '/home');
    expect(
      c.read(profileCatalogProvider).single.birthDate,
      DateTime(1960, 2, 1),
    );
  });

  for (final path in ['welcome', 'sign-in', 'sign-up', 'scan', 'form']) {
    testWidgets('$path fits 360 px at 200% text', (tester) async {
      final scanner = FakeScanner();
      final c = await openSignedOut(
        tester,
        scanner: scanner,
        scale: 2,
        size: const Size(360, 800),
      );
      final router = c.read(appRouterProvider);
      switch (path) {
        case 'sign-in' || 'sign-up':
          router.push('/$path');
        case 'scan':
          c.read(authSessionProvider.notifier).signUp('0987654321', '123456');
          await tester.pumpAndSettle();
          router.push('/profile-new/scan?for=self');
        case 'form':
          c.read(authSessionProvider.notifier).signUp('0987654321', '123456');
          await tester.pumpAndSettle();
          router.push('/profile-new/scan?for=family');
          await tester.pumpAndSettle();
          scanner.emit(sampleCccdQr);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
