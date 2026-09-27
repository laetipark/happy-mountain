import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

import '../domain/contracts.dart';

/// Only foreground permission is requested. Tracking stops on app suspension.
class DeviceLocationService implements LocationService {
  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 25,
  );

  Future<void> _requestAccess() async {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationFailure.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationFailure.deniedForever);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationException(LocationFailure.denied);
    }
  }

  @override
  Future<GeoPoint> currentPosition() async {
    await _requestAccess();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return GeoPoint(position.latitude, position.longitude);
  }

  @override
  Stream<GeoPoint> get changes =>
      Geolocator.getPositionStream(locationSettings: _settings)
          .map((position) => GeoPoint(position.latitude, position.longitude));

  @override
  Future<void> openSettings() async {
    // Browsers cannot open system settings. The UI shows browser instructions.
    if (kIsWeb) return;
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
