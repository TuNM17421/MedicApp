import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/core/widgets/app_widgets.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/smart/application/smart_controller.dart';

import '../app_navigation_test.dart' show openApp;
import '../booking_flow_test.dart' show next, press;
import 'smart_fakes.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('smart-confirm')),
      matching: find.byType(AppPrimaryButton),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home entry: type a request, review, confirm, pay', (
    tester,
  ) async {
    final gateway = FakeGateway(
      (_, _, _) async => reply(
        status: 'ready',
        version: 2,
        fields: readyFields,
        sources: const {'departmentId': 'suggested'},
      ),
    );
    final c = await openApp(
      tester,
      size: const Size(412, 915),
      overrides: [
        smartGatewayProvider.overrideWithValue(gateway),
        voiceCaptureProvider.overrideWithValue(FakeCapture()),
      ],
    );
    await tapKey(tester, 'home-smart');
    expect(find.text('Đặt lịch thông minh'), findsOneWidget);
    expect(find.byKey(const Key('smart-simulated')), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-nav')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('smart-input')),
      'Tôi đau khớp gối, muốn khám sáng sớm nhất ở An Bình',
    );
    await tester.tap(find.byKey(const Key('smart-send')));
    await tester.pumpAndSettle();
    expect(find.text('Đề xuất lịch khám'), findsOneWidget);
    expect(find.text('Mô tả có nhắc tới đau khớp.'), findsOneWidget);
    expect(find.text('Phạm Văn Hòa'), findsWidgets);

    await confirm(tester);
    final session = c.read(bookingSessionProvider);
    expect(session.stage, BookingStage.payment);
    expect(session.draft.departmentId, 'bones');
    expect(find.text('Cách thanh toán'), findsOneWidget);

    await press(tester, 'payment-wallet');
    await next(tester);
    expect(find.text('Đặt lịch thành công'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('urgent sign: names it, offers 115 and stops booking', (
    tester,
  ) async {
    final gateway = FakeGateway(
      (_, _, _) async => reply(
        status: 'urgent',
        version: 2,
        urgent: const {
          'signs': ['ngất'],
          'by': ['list'],
        },
      ),
    );
    await openApp(
      tester,
      size: const Size(412, 915),
      overrides: [
        smartGatewayProvider.overrideWithValue(gateway),
        voiceCaptureProvider.overrideWithValue(FakeCapture()),
      ],
    );
    await tapKey(tester, 'home-smart');
    await tester.enterText(
      find.byKey(const Key('smart-input')),
      'Bố tôi vừa ngất xỉu',
    );
    await tester.tap(find.byKey(const Key('smart-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smart-urgent')), findsOneWidget);
    expect(find.textContaining('Bạn có nhắc tới: ngất.'), findsOneWidget);
    expect(find.byKey(const Key('smart-call-115')), findsOneWidget);
    expect(find.byKey(const Key('smart-urgent-map')), findsOneWidget);
    expect(find.byKey(const Key('smart-input')), findsNothing);
    expect(find.byKey(const Key('smart-confirm')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('from the department step: context kept, back at payment', (
    tester,
  ) async {
    final gateway = FakeGateway(
      (_, _, _) async => reply(
        status: 'ready',
        version: 2,
        fields: {
          ...readyFields,
          'department_id': 'eyes',
          'department_reason': null,
        },
      ),
      initial: reply(
        fields: const {
          'patient_id': 'self',
          'visit_type': 'service',
          'facility_id': 'anbinh',
        },
        question: const {
          'field': 'departmentId',
          'text': 'Bạn đang gặp vấn đề gì, hoặc muốn khám chuyên khoa nào?',
          'options': [
            {'value': 'eyes', 'label': 'Mắt'},
            {'value': 'bones', 'label': 'Cơ Xương Khớp'},
          ],
        },
      ),
    );
    final c = await openApp(
      tester,
      location: '/booking',
      size: const Size(412, 915),
      overrides: [
        smartGatewayProvider.overrideWithValue(gateway),
        voiceCaptureProvider.overrideWithValue(FakeCapture()),
      ],
    );
    await press(tester, 'type-service');
    await next(tester);
    await press(tester, 'booking-patient-self');
    await next(tester);
    await press(tester, 'facility-anbinh');
    await next(tester);
    await press(tester, 'booking-smart');
    expect(gateway.context!.patientId, 'self');
    expect(gateway.context!.facilityId, 'anbinh');
    expect(gateway.context!.type, VisitType.service);
    expect(find.text('Bạn đặt lịch khám cho ai?'), findsNothing);

    await tapKey(tester, 'smart-option-eyes');
    expect(gateway.connection!.calls, ['choice:departmentId=eyes']);
    await confirm(tester);
    final session = c.read(bookingSessionProvider);
    expect(session.stage, BookingStage.payment);
    expect(session.draft.departmentId, 'eyes');
    expect(find.text('Cách thanh toán'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proposal and listening bar fit 360 px at 200% text', (
    tester,
  ) async {
    final capture = FakeCapture();
    final gateway = FakeGateway(
      (_, _, _) async =>
          reply(status: 'ready', version: 2, fields: readyFields),
      voice: true,
    );
    await openApp(
      tester,
      location: '/smart',
      scale: 2,
      overrides: [
        smartGatewayProvider.overrideWithValue(gateway),
        voiceCaptureProvider.overrideWithValue(capture),
      ],
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('smart-input')), 'khám');
    await tester.tap(find.byKey(const Key('smart-send')));
    await tester.pumpAndSettle();
    expect(find.text('Đề xuất lịch khám'), findsOneWidget);
    await tester.tap(find.byKey(const Key('smart-mic')));
    await tester.pumpAndSettle();
    expect(find.text('Đang kết nối micro…'), findsOneWidget);
    expect(find.byKey(const Key('smart-confirm')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
