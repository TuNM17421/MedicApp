import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/data/booking_catalog.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';
import 'package:medic_app/features/facilities/application/nearby_providers.dart';
import 'package:medic_app/features/facilities/data/device_location.dart';

import '../app_navigation_test.dart' show openApp;
import '../booking_flow_test.dart' show next, press;

/// Cầu Giấy: Sông Xanh is nearest, An Bình next, Hòa Lạc far away.
const caugiay = LatLng(21.0300, 105.8000);

class FakeLocation implements DeviceLocation {
  FakeLocation(this.access, {this.position = caugiay, this.afterRequest});
  LocationAccess access;
  final LatLng? position;
  final LocationAccess? afterRequest;
  int requests = 0, settings = 0;

  @override
  Future<LocationAccess> check() async => access;

  @override
  Future<LocationAccess> request() async {
    requests++;
    return access = afterRequest ?? access;
  }

  @override
  Future<LatLng?> current() async => position;

  @override
  Future<void> openSettings(LocationAccess access) async => settings++;
}

final _blank = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class BlankTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_blank);
}

Future<void> toFacilityStep(
  WidgetTester tester, {
  bool insurance = false,
}) async {
  await press(tester, insurance ? 'type-insurance' : 'type-service');
  await next(tester);
  await press(
    tester,
    insurance ? 'booking-patient-mother' : 'booking-patient-self',
  );
  await next(tester);
}

void main() {
  group('distance', () {
    test('ranks facilities nearest first and formats like a person', () {
      final ranked = facilitiesByDistance(caugiay, BookingCatalog.facilities);
      expect(ranked.map((item) => item.facility.id), [
        'songxanh',
        'anbinh',
        'hoalac',
      ]);
      expect(ranked.first.km, inInclusiveRange(1, 3));
      expect(formatDistance(0.42), '400 m');
      expect(formatDistance(2.345), '2,3 km');
      expect(formatDistance(28.6), '29 km');
    });

    test('BHYT skips facilities without BHYT; department is preferred', () {
      const draft = BookingDraft(id: 'd');
      expect(nearestFor(caugiay, draft)?.facility.id, 'songxanh');
      expect(
        nearestFor(
          caugiay,
          draft.copyWith(type: VisitType.insurance),
        )?.facility.id,
        'anbinh',
      );
      expect(
        nearestFor(
          caugiay,
          draft.copyWith(type: VisitType.service, departmentId: 'children'),
        )?.facility.id,
        'anbinh',
      );
      expect(nearestFor(null, draft), isNull);
    });
  });

  testWidgets('allowed before: the nearest facility is suggested on its own', (
    tester,
  ) async {
    final location = FakeLocation(LocationAccess.granted);
    final c = await openApp(
      tester,
      location: '/booking',
      size: const Size(412, 915),
      overrides: [deviceLocationProvider.overrideWithValue(location)],
    );
    await toFacilityStep(tester);
    expect(location.requests, 0);
    expect(find.text('Gần bạn nhất'), findsOneWidget);
    expect(find.text('Bệnh viện Sông Xanh'), findsWidgets);
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('facility-songxanh')),
    );
    final far = tester.getTopLeft(
      find.byKey(const ValueKey('facility-hoalac')),
    );
    expect(first.dy, lessThan(far.dy));
    await press(tester, 'nearby-choose');
    expect(c.read(bookingSessionProvider).draft.facilityId, 'songxanh');
    expect(find.text('Đã chọn cơ sở này'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BHYT visit suggests the nearest facility that takes BHYT', (
    tester,
  ) async {
    await openApp(
      tester,
      location: '/booking',
      size: const Size(412, 915),
      overrides: [
        deviceLocationProvider.overrideWithValue(
          FakeLocation(LocationAccess.granted),
        ),
      ],
    );
    await toFacilityStep(tester, insurance: true);
    expect(
      find.descendant(
        of: find.byKey(const Key('nearby-suggestion')),
        matching: find.text('Phòng khám Đa khoa An Bình'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('not asked yet: no prompt until the user taps; refusal is calm', (
    tester,
  ) async {
    final location = FakeLocation(
      LocationAccess.notAsked,
      afterRequest: LocationAccess.denied,
    );
    final c = await openApp(
      tester,
      location: '/booking',
      size: const Size(412, 915),
      overrides: [deviceLocationProvider.overrideWithValue(location)],
    );
    await toFacilityStep(tester);
    expect(location.requests, 0);
    expect(find.text('Dùng vị trí hiện tại'), findsOneWidget);
    await press(tester, 'nearby-locate');
    expect(location.requests, 1);
    expect(
      find.textContaining('Bạn chưa cho phép dùng vị trí'),
      findsOneWidget,
    );
    await press(tester, 'facility-anbinh');
    await next(tester);
    expect(c.read(bookingSessionProvider).stage, BookingStage.department);
  });

  testWidgets('denied for good or location off: offer the right settings', (
    tester,
  ) async {
    final location = FakeLocation(LocationAccess.deniedForever);
    await openApp(
      tester,
      location: '/booking',
      size: const Size(412, 915),
      overrides: [deviceLocationProvider.overrideWithValue(location)],
    );
    await toFacilityStep(tester);
    await press(tester, 'nearby-locate');
    expect(location.requests, 0);
    expect(find.text('Mở Cài đặt'), findsOneWidget);
    await press(tester, 'nearby-locate');
    expect(location.settings, 1);
  });

  testWidgets('map from Home: all pins, locate jumps to nearest, book there', (
    tester,
  ) async {
    final location = FakeLocation(
      LocationAccess.notAsked,
      afterRequest: LocationAccess.granted,
    );
    final c = await openApp(
      tester,
      location: '/facility-map',
      size: const Size(412, 915),
      overrides: [
        deviceLocationProvider.overrideWithValue(location),
        mapTileProviderProvider.overrideWithValue(BlankTiles()),
      ],
    );
    expect(location.requests, 0);
    for (final facility in BookingCatalog.facilities) {
      expect(find.bySemanticsLabel(facility.name), findsOneWidget);
    }
    expect(find.text('Gần bạn nhất'), findsNothing);
    await tester.tap(find.byKey(const Key('map-locate')));
    await tester.pumpAndSettle();
    expect(location.requests, 1);
    expect(find.bySemanticsLabel('Vị trí của bạn'), findsOneWidget);
    expect(find.text('Gần bạn nhất'), findsOneWidget);
    expect(find.text('Bệnh viện Sông Xanh'), findsOneWidget);
    expect(find.text('Cách 2,0 km'), findsOneWidget);
    await tester.tap(find.text('Đặt lịch tại đây'));
    await tester.pumpAndSettle();
    final session = c.read(bookingSessionProvider);
    expect(session.stage, BookingStage.type);
    expect(session.draft.facilityId, 'songxanh');
    expect(find.textContaining('Đã chọn sẵn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map from booking: pick a pin and return with it chosen', (
    tester,
  ) async {
    final c = await openApp(
      tester,
      location: '/booking',
      size: const Size(412, 915),
      overrides: [
        deviceLocationProvider.overrideWithValue(
          FakeLocation(LocationAccess.notAsked),
        ),
        mapTileProviderProvider.overrideWithValue(BlankTiles()),
      ],
    );
    await toFacilityStep(tester, insurance: true);
    await press(tester, 'nearby-map');
    expect(find.text('Cơ sở khám trên bản đồ'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Bệnh viện Sông Xanh'));
    await tester.pumpAndSettle();
    expect(find.text('Cơ sở này không hỗ trợ khám BHYT.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Trung tâm Y tế Hòa Lạc'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chọn cơ sở này'));
    await tester.pumpAndSettle();
    expect(find.text('Cơ sở khám trên bản đồ'), findsNothing);
    expect(c.read(bookingSessionProvider).draft.facilityId, 'hoalac');
    expect(c.read(bookingSessionProvider).stage, BookingStage.facility);
  });
}
