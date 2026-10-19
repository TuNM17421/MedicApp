import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../booking/data/booking_catalog.dart';
import '../../booking/domain/booking_models.dart';
import '../data/device_location.dart';

final deviceLocationProvider = Provider<DeviceLocation>(
  (ref) => const GeolocatorDeviceLocation(),
);

/// OpenStreetMap tiles by default; tests swap in offline tiles.
final mapTileProviderProvider = Provider<TileProvider>(
  (ref) => NetworkTileProvider(),
);

enum NearbyPhase {
  idle,
  locating,
  ready,
  denied,
  deniedForever,
  serviceOff,
  unavailable,
}

class NearbyState {
  const NearbyState({this.phase = NearbyPhase.idle, this.position});
  final NearbyPhase phase;

  /// Approximate phone position, kept in memory for this app run only.
  final LatLng? position;

  /// Settings can fix these; a retry alone cannot.
  bool get needsSettings =>
      phase == NearbyPhase.deniedForever || phase == NearbyPhase.serviceOff;
}

typedef FacilityDistance = ({Facility facility, double km});

const _distance = Distance();

/// Nearest first. Straight-line distance, enough to rank a few facilities.
List<FacilityDistance> facilitiesByDistance(
  LatLng from,
  Iterable<Facility> facilities,
) => [
  for (final facility in facilities)
    (
      facility: facility,
      km: _distance.as(LengthUnit.Meter, from, facility.location) / 1000,
    ),
]..sort((a, b) => a.km.compareTo(b.km));

/// Same rule as the booking flow: BHYT visits need a facility that takes BHYT.
bool facilityAllowed(Facility facility, BookingDraft? draft) =>
    draft?.type != VisitType.insurance || facility.acceptsInsurance;

/// Nearest facility the draft can use, preferring one that already has the
/// chosen department. Null without a position.
FacilityDistance? nearestFor(LatLng? from, BookingDraft? draft) {
  if (from == null) return null;
  final ranked = facilitiesByDistance(
    from,
    BookingCatalog.facilities,
  ).where((item) => facilityAllowed(item.facility, draft)).toList();
  final department = draft?.departmentId;
  return ranked
          .where(
            (item) =>
                department == null ||
                item.facility.departments.contains(department),
          )
          .firstOrNull ??
      ranked.firstOrNull;
}

String formatDistance(double km) {
  if (km < 1) return '${(km * 1000 / 50).round() * 50} m';
  if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  return '${km.round()} km';
}

final nearbyProvider = NotifierProvider<NearbyController, NearbyState>(
  NearbyController.new,
);

class NearbyController extends Notifier<NearbyState> {
  DeviceLocation get _device => ref.read(deviceLocationProvider);

  @override
  NearbyState build() => const NearbyState();

  /// Suggests nearby facilities on its own only when the user already allowed
  /// location before. Never shows a system prompt.
  Future<void> refreshIfAllowed() async {
    if (state.phase == NearbyPhase.locating ||
        state.phase == NearbyPhase.ready) {
      return;
    }
    try {
      if (await _device.check() == LocationAccess.granted) await _read();
    } on Exception {
      // No location plugin (tests, unsupported platform): stay quiet.
    }
  }

  /// The user tapped "Dùng vị trí hiện tại": ask once, then read a position.
  Future<void> locate() async {
    if (state.phase == NearbyPhase.locating) return;
    state = NearbyState(phase: NearbyPhase.locating, position: state.position);
    try {
      var access = await _device.check();
      if (access == LocationAccess.notAsked) access = await _device.request();
      switch (access) {
        case LocationAccess.granted:
          await _read();
        case LocationAccess.serviceOff:
          state = const NearbyState(phase: NearbyPhase.serviceOff);
        case LocationAccess.deniedForever:
          state = const NearbyState(phase: NearbyPhase.deniedForever);
        case LocationAccess.notAsked || LocationAccess.denied:
          state = const NearbyState(phase: NearbyPhase.denied);
      }
    } on Exception {
      state = const NearbyState(phase: NearbyPhase.unavailable);
    }
  }

  Future<void> _read() async {
    state = NearbyState(phase: NearbyPhase.locating, position: state.position);
    final position = await _device.current();
    state = position == null
        ? const NearbyState(phase: NearbyPhase.unavailable)
        : NearbyState(phase: NearbyPhase.ready, position: position);
  }

  Future<void> openSettings() async {
    final access = state.phase == NearbyPhase.serviceOff
        ? LocationAccess.serviceOff
        : LocationAccess.deniedForever;
    try {
      await _device.openSettings(access);
    } on Exception {
      return;
    }
  }
}
