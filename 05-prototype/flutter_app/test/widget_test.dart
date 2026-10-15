import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medic_app/app/theme/app_theme.dart';
import 'package:medic_app/core/widgets/app_choices.dart';
import 'package:medic_app/core/widgets/app_primitives.dart';
import 'package:medic_app/features/design_preview/design_preview_page.dart';
import 'package:medic_app/main.dart';

Future<void> pumpPreview(WidgetTester tester, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: const RepaintBoundary(
        key: Key('preview-capture'),
        child: DesignPreviewPage(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('BeVietnamPro');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
  });

  testWidgets('app opens the home shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedicApp()));
    await tester.pumpAndSettle();
    expect(find.text('MedicApp'), findsOneWidget);
    expect(find.text('Đặt khám dễ dàng cho cả nhà'), findsOneWidget);
    expect(find.text('Flutter Demo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(412, 915)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('preview fits $size at text scale $scale', (tester) async {
        await pumpPreview(tester, size, scale);
        expect(tester.takeException(), isNull);
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('design-preview-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final position = scrollable.position;
        for (
          double offset = 0;
          offset < position.maxScrollExtent;
          offset += 500
        ) {
          position.jumpTo(offset);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'At scroll offset $offset',
          );
        }
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('choice announces selection and lets the user change it', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppChoiceCard(
              key: const Key('choice'),
              title: 'Người khám mẫu',
              selected: selected,
              onTap: () => setState(() => selected = !selected),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('choice'))),
      matchesSemantics(
        label: 'Người khám mẫu',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byKey(const Key('choice')));
    await tester.pump();
    expect(selected, isTrue);
    expect(
      tester.getSemantics(find.byKey(const Key('choice'))),
      matchesSemantics(
        label: 'Người khám mẫu',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('unavailable slots and busy buttons do not submit', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              AppSelectionChip(
                label: '09:00',
                enabled: false,
                onTap: () => calls++,
              ),
              AppPrimaryButton(
                label: 'Tiếp tục',
                isLoading: true,
                onPressed: () => calls++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('09:00'));
    await tester.tap(find.text('Đang xử lý…'));
    expect(calls, 0);
    expect(find.text('Hết chỗ'), findsOneWidget);
  });

  testWidgets('preview card and slot selection work without booking routes', (
    tester,
  ) async {
    await pumpPreview(tester, const Size(360, 800), 1);
    await tester.ensureVisible(find.byKey(const Key('insurance-choice')));
    await tester.tap(find.byKey(const Key('insurance-choice')));
    await tester.pump();
    expect(
      tester
          .widget<AppChoiceCard>(find.byKey(const Key('insurance-choice')))
          .selected,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('slot-08:00')));
    await tester.tap(find.byKey(const ValueKey('slot-08:00')));
    await tester.pump();
    expect(
      tester
          .widget<AppSelectionChip>(find.byKey(const ValueKey('slot-08:00')))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final config in [
    (size: const Size(360, 800), scale: 1.0, name: 'preview-360'),
    (size: const Size(412, 915), scale: 1.0, name: 'preview-412'),
    (size: const Size(360, 800), scale: 2.0, name: 'preview-360-large-text'),
  ]) {
    testWidgets('visual baseline ${config.name}', (tester) async {
      await pumpPreview(tester, config.size, config.scale);
      await expectLater(
        find.byKey(const Key('preview-capture')),
        matchesGoldenFile('goldens/${config.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('visual baseline choice components', (tester) async {
    await pumpPreview(tester, const Size(360, 800), 1);
    await tester.ensureVisible(find.text('Thẻ lựa chọn'));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byKey(const Key('preview-capture')),
      matchesGoldenFile('goldens/preview-controls-360.png'),
    );
    expect(tester.takeException(), isNull);
  });
}
