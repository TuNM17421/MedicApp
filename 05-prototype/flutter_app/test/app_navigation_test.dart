import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/router/app_router.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/core/widgets/app_headers.dart';
import 'package:medic_app/main.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/data/booking_repository.dart';

Future<ProviderContainer> openApp(
  WidgetTester tester, {
  String location = '/home',
  double scale = 1,
  Size size = const Size(360, 800),
  bool disableAnimations = true,
  bool accessibleNavigation = false,
  BookingRepository? bookingRepository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      bookingTodayProvider.overrideWithValue(DateTime(2026, 10, 14)),
      if (bookingRepository != null)
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
      appRouterProvider.overrideWith((ref) {
        final router = createAppRouter(initialLocation: location);
        ref.onDispose(router.dispose);
        return router;
      }),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: const Key('shell-capture'),
        child: MedicApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: disableAnimations,
              accessibleNavigation: accessibleNavigation,
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapTab(WidgetTester tester, String title) async {
  final target = find.descendant(
    of: find.byKey(const Key('app-bottom-nav')),
    matching: find.byKey(ValueKey('nav-$title')),
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('BeVietnamPro');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      font.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
  });

  testWidgets(
    'tabs retain nested history and selected profile; Android Back unwinds it',
    (tester) async {
      final container = await openApp(tester);
      await tapTab(tester, 'Hồ sơ');
      await tapText(tester, 'Phạm Thị Lan');
      await tapText(tester, 'Xem hồ sơ đang chọn');
      expect(find.text('Chi tiết hồ sơ'), findsOneWidget);
      await tapTab(tester, 'Tài khoản');
      expect(find.text('Thông tin tài khoản'), findsOneWidget);
      await tapTab(tester, 'Hồ sơ');
      expect(find.text('Chi tiết hồ sơ'), findsOneWidget);
      expect(find.text('Phạm Thị Lan'), findsOneWidget);
      expect(container.read(activeProfileProvider).id, 'mother');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ gia đình'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('MedicApp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reading notices updates badge without recreating the router or losing history',
    (tester) async {
      final container = await openApp(tester);
      final router = container.read(appRouterProvider);
      expect(
        tester
            .widget<AppBottomNav>(find.byKey(const Key('app-bottom-nav')))
            .unreadCount,
        2,
      );
      await tapTab(tester, 'Thông báo');
      await tapText(tester, 'Chào mừng đến với MedicApp');
      expect(find.text('Chi tiết thông báo'), findsOneWidget);
      expect(container.read(unreadCountProvider), 1);
      expect(container.read(appRouterProvider), same(router));
      await tapTab(tester, 'Trang chủ');
      await tapTab(tester, 'Thông báo');
      expect(find.text('Chi tiết thông báo'), findsOneWidget);
      await tapText(tester, 'Quay lại');
      await tapText(tester, 'Đánh dấu tất cả đã đọc');
      expect(container.read(unreadCountProvider), 0);
      expect(
        tester
            .widget<AppBottomNav>(find.byKey(const Key('app-bottom-nav')))
            .unreadCount,
        0,
      );
    },
  );

  testWidgets('booking is a root overlay and returns to the previous tab', (
    tester,
  ) async {
    final container = await openApp(tester, location: '/profiles/mother');
    await tapTab(tester, 'Đặt lịch');
    expect(find.text('Khám BHYT'), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-nav')), findsNothing);
    expect(container.read(activeProfileProvider).id, 'self');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết hồ sơ'), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-nav')), findsOneWidget);
  });

  testWidgets('direct booking link has a safe home fallback', (tester) async {
    await openApp(tester, location: '/booking');
    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('MedicApp'), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-nav')), findsOneWidget);
  });

  testWidgets(
    'direct notification link selects its tab and marks the notice read',
    (tester) async {
      final container = await openApp(
        tester,
        location: '/notifications/welcome',
      );
      expect(
        tester
            .widget<AppBottomNav>(find.byKey(const Key('app-bottom-nav')))
            .selectedIndex,
        3,
      );
      expect(container.read(unreadCountProvider), 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('1 thông báo chưa đọc'), findsOneWidget);
    },
  );

  testWidgets('invalid routes and IDs show recovery instead of throwing', (
    tester,
  ) async {
    final container = await openApp(tester, location: '/profiles/missing');
    expect(find.text('Không tìm thấy hồ sơ'), findsOneWidget);
    container.read(appRouterProvider).go('/missing-page');
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy trang'), findsOneWidget);
    await tapText(tester, 'Về trang chủ');
    expect(find.text('MedicApp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(412, 915)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('shell tabs fit $size with text scale $scale', (
        tester,
      ) async {
        await openApp(tester, size: size, scale: scale);
        for (final title in ['Hồ sơ', 'Thông báo', 'Tài khoản', 'Trang chủ']) {
          await tapTab(tester, title);
          expect(tester.takeException(), isNull, reason: title);
        }
      });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('shell visual baseline at scale $scale', (tester) async {
      await openApp(tester, scale: scale);
      await expectLater(
        find.byKey(const Key('shell-capture')),
        matchesGoldenFile('goldens/shell-home-${scale.toInt()}x.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
