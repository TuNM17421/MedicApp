import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum LocationAccess { notAsked, granted, denied, deniedForever, serviceOff }

/// Phone location. Approximate (coarse) position only, read when the user
/// asks for nearby facilities; it stays in memory and is never sent anywhere.
abstract interface class DeviceLocation {
  /// Current state without showing any system prompt.
  Future<LocationAccess> check();

  /// Shows the system permission prompt when Android still allows it.
  Future<LocationAccess> request();

  /// Null when no position arrives in time.
  Future<LatLng?> current();

  /// App settings when permission is denied for good, location settings when
  /// the location service is off.
  Future<void> openSettings(LocationAccess access);
}

class GeolocatorDeviceLocation implements DeviceLocation {
  const GeolocatorDeviceLocation();

  static LocationAccess _map(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationAccess.notAsked,
      };

  @override
  Future<LocationAccess> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    final access = _map(await Geolocator.requestPermission());
    // Android answers "denied" again when the user dismisses the prompt.
    return access == LocationAccess.notAsked ? LocationAccess.denied : access;
  }

  @override
  Future<LatLng?> current() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } on Exception {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : LatLng(last.latitude, last.longitude);
    }
  }

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
