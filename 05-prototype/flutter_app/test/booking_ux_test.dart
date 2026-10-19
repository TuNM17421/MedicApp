import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:medic_app/app/theme/app_theme.dart';
import 'package:medic_app/core/widgets/app_widgets.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/booking/presentation/booking_ux.dart';

import 'app_navigation_test.dart' show openApp, tapText;
import 'booking_flow_test.dart' show chooseToReview, press, next;
import 'booking_state_test.dart' show ControlledRepository;

void main() {
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
    'step entrance settles, does not repeat on selection, and never duplicates actions',
    (tester) async {
      await openApp(tester, location: '/booking', disableAnimations: false);
      await press(tester, 'type-service');
      await next(tester);
      expect(find.byKey(const Key('type-service')), findsNothing);
      expect(find.byKey(const Key('booking-action')), findsOneWidget);
      expect(find.byKey(const Key('booking-patient-self')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      await press(tester, 'booking-patient-self');
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final accessibility in [false, true]) {
    testWidgets(
      'reduced motion is static (accessibleNavigation=$accessibility)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                disableAnimations: !accessibility,
                accessibleNavigation: accessibility,
              ),
              child: const Scaffold(
                body: BookingStepEntrance(
                  step: 'loading',
                  child: BookingSlotsSkeleton(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Animate), findsNothing);
        expect(
          tester
              .widget<Skeletonizer>(
                find.byKey(const Key('booking-slots-skeleton')),
              )
              .effect,
          isA<SolidColorEffect>(),
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'skeleton announces one loading state, blocks Next, resolves and retries',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledRepository();
      final c = await openApp(
        tester,
        location: '/booking',
        bookingRepository: repository,
        disableAnimations: false,
      );
      final a = c.read(bookingSessionProvider.notifier);
      a.chooseType(VisitType.service);
      a.choosePatient('self');
      a.chooseFacility('anbinh');
      a.chooseDepartment('general');
      a.chooseDoctor(DoctorMode.any);
      a.edit(BookingStage.dateTime);
      final loading = a.chooseDate(DateTime(2026, 10, 15));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('booking-slots-skeleton')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Đang tải giờ khám. Vui lòng chờ.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('booking-slot-09:00')), findsNothing);
      final action = find.descendant(
        of: find.byKey(const Key('booking-action')),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      repository.pending[0].completeError(
        const BookingException('Không tải được giờ khám. Vui lòng thử lại.'),
      );
      await loading;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('booking-slots-skeleton')), findsNothing);
      final retry = a.loadSlots();
      await tester.pump();
      expect(find.byKey(const Key('booking-slots-skeleton')), findsOneWidget);
      repository.pending[1].complete([
        BookingSlot(DateTime(2026, 10, 15), '09:00', 'anbinh-general-0'),
      ]);
      await retry;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('booking-slots-skeleton')), findsNothing);
      expect(find.textContaining('Có 1 khung giờ còn chỗ'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('selecting a time keeps its height and announces selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Widget scene(bool selected) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            child: AppSelectionChip(
              key: const Key('slot'),
              label: '09:30',
              selected: selected,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene(false));
    final before = tester.getSize(find.byKey(const Key('slot')));
    await tester.pumpWidget(scene(true));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('slot'))), before);
    expect(
      tester
          .getSemantics(find.byKey(const Key('slot')))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  for (final sample in [
    (size: const Size(320, 640), scale: 2.5),
    (size: const Size(800, 360), scale: 2.0),
  ]) {
    testWidgets(
      'complete service flow at ${sample.size} with ${sample.scale}x text',
      (tester) async {
        final c = await openApp(
          tester,
          location: '/booking',
          size: sample.size,
          scale: sample.scale,
        );
        await chooseToReview(tester);
        expect(c.read(bookingSessionProvider).stage, BookingStage.review);
        await next(tester);
        await press(tester, 'payment-wallet');
        await next(tester);
        expect(
          c.read(appointmentsProvider).records.single.receipt.status,
          PaymentStatus.confirmed,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'invalid contact feedback is revealed after scrolling and dismissing keyboard',
    (tester) async {
      final c = await openApp(tester, location: '/booking', scale: 2);
      await chooseToReview(tester);
      await press(tester, 'booking-contact-phone');
      await tester.enterText(
        find.byKey(const Key('booking-contact-phone')),
        '123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await next(tester);
      expect(c.read(bookingSessionProvider).stage, BookingStage.review);
      expect(
        find.textContaining('Kiểm tra tên người nhận thông báo').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'patient sheet remains usable with large text, keyboard and safe insets',
    (tester) async {
      final c = await openApp(tester, location: '/booking', scale: 2);
      tester.view.padding = const FakeViewPadding(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24,
      );
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await press(tester, 'type-service');
      await next(tester);
      await tapText(tester, 'Thêm người khám');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('new-patient-name')));
      await tester.enterText(
        find.byKey(const Key('new-patient-name')),
        'Nguyễn Thị Mai',
      );
      await tester.ensureVisible(find.byKey(const Key('new-patient-dob')));
      await tester.enterText(
        find.byKey(const Key('new-patient-dob')),
        '12/08/1964',
      );
      await tapText(tester, 'Lưu người khám');
      expect(c.read(bookingSessionProvider).draft.patientId, startsWith('P'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large-text date and static skeleton visual baselines', (
    tester,
  ) async {
    final repository = ControlledRepository();
    final c = await openApp(
      tester,
      location: '/booking',
      scale: 2,
      bookingRepository: repository,
    );
    final a = c.read(bookingSessionProvider.notifier);
    a.chooseType(VisitType.service);
    a.choosePatient('self');
    a.chooseFacility('anbinh');
    a.chooseDepartment('general');
    a.chooseDoctor(DoctorMode.any);
    a.edit(BookingStage.dateTime);
    final loading = a.chooseDate(DateTime(2026, 10, 15));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byType(BookingSlotsSkeleton)),
      alignment: 0,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('shell-capture')),
      matchesGoldenFile('goldens/booking-skeleton-360-large-text.png'),
    );
    repository.pending[0].complete([
      BookingSlot(DateTime(2026, 10, 15), '09:00', 'anbinh-general-0'),
      BookingSlot(DateTime(2026, 10, 15), '09:30', null),
    ]);
    await loading;
    await tester.pumpAndSettle();
    await press(tester, 'booking-slot-09:00');
    await expectLater(
      find.byKey(const Key('shell-capture')),
      matchesGoldenFile('goldens/booking-slots-360-large-text.png'),
    );
    expect(tester.takeException(), isNull);
  });
}
