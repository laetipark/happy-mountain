import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/contracts.dart';
import '../platform/kakao_map.dart';
import 'app_config.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.config,
    required this.places,
    required this.weatherRepository,
    required this.historyRepository,
    required this.location,
    this.debounceDuration = const Duration(milliseconds: 450),
  });

  final AppConfig config;
  final PlaceRepository places;
  final WeatherRepository weatherRepository;
  final WarningHistoryRepository historyRepository;
  final LocationService location;
  final Duration debounceDuration;

  GeoPoint center = GeoPoint.seoul;
  GeoPoint? myLocation;
  int cameraRevision = 0;
  List<MountainPlace> mountains = [];
  WeatherSnapshot? weather;
  WarningDataset? history;
  HistoryFilter? filter;
  List<WarningRecord> filteredRecords = [];
  List<WarningRecord> mapRecords = [];
  String? mountainError;
  String? weatherError;
  String? historyError;
  String? locationError;
  String? geocodeError;
  bool loadingMountains = false;
  bool loadingWeather = false;
  bool loadingHistory = false;
  bool locating = false;
  bool geocoding = false;
  bool needsLocationSettings = false;
  int markerLimit = 60;

  final Map<String, GeoPoint?> _addressCache = {};
  Timer? _debounce;
  StreamSubscription<GeoPoint>? _locationSubscription;
  int _viewportGeneration = 0;
  int _geocodeGeneration = 0;
  int _locationGeneration = 0;
  bool _disposed = false;
  bool _started = false;
  bool _foreground = true;
  bool _locationGranted = false;
  bool _defaultDates = true;
  int _trackingGeneration = 0;
  String? _viewportKey;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void initialize({bool? requestLocation}) {
    if (_started || _disposed) return;
    _started = true;
    unawaited(loadHistory());
    refreshViewport();
    if (requestLocation ?? !config.web) unawaited(locate());
  }

  void cameraIdle(GeoPoint point) {
    final key =
        '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
    if (_viewportKey == key || _disposed) return;
    _viewportKey = key;
    center = point;
    final generation = ++_viewportGeneration;
    _debounce?.cancel();
    _debounce = Timer(
      debounceDuration,
      () => _fetchViewport(point, generation),
    );
  }

  void refreshViewport() {
    if (_disposed) return;
    _debounce?.cancel();
    _viewportKey =
        '${center.latitude.toStringAsFixed(4)},${center.longitude.toStringAsFixed(4)}';
    unawaited(_fetchViewport(center, ++_viewportGeneration));
  }

  Future<void> _fetchViewport(GeoPoint point, int generation) async {
    if (_disposed || generation != _viewportGeneration) return;
    loadingMountains = config.placesEnabled;
    loadingWeather = config.weatherEnabled;
    mountains = [];
    weather = null;
    mountainError = !config.placesEnabled
        ? '주변 산 검색은 장소 연결 설정 후 사용할 수 있습니다.'
        : null;
    weatherError = !config.weatherEnabled
        ? '날씨는 기상청 연결 설정 후 사용할 수 있습니다.'
        : null;
    _emit();
    await Future.wait([
      if (config.placesEnabled)
        () async {
          try {
            final result = await places.searchMountains(point);
            if (_disposed || generation != _viewportGeneration) return;
            mountains = result;
          } catch (error) {
            if (_disposed || generation != _viewportGeneration) return;
            mountainError = _message(error, '주변 산을 찾지 못했습니다. 다시 시도해 주세요.');
          } finally {
            if (!_disposed && generation == _viewportGeneration) {
              loadingMountains = false;
              _emit();
            }
          }
        }(),
      if (config.weatherEnabled)
        () async {
          try {
            final result = await weatherRepository.fetchWeather(point);
            if (_disposed || generation != _viewportGeneration) return;
            weather = result;
          } catch (error) {
            if (_disposed || generation != _viewportGeneration) return;
            weatherError = _message(error, '날씨 정보를 불러오지 못했습니다. 다시 시도해 주세요.');
          } finally {
            if (!_disposed && generation == _viewportGeneration) {
              loadingWeather = false;
              _emit();
            }
          }
        }(),
    ]);
  }

  Future<void> locate() async {
    if (locating || _disposed) return;
    final generation = ++_locationGeneration;
    locating = true;
    locationError = null;
    needsLocationSettings = false;
    _emit();
    try {
      final point = await location.currentPosition();
      if (_disposed || generation != _locationGeneration || !_foreground) {
        return;
      }
      myLocation = point;
      center = point;
      cameraRevision++;
      _locationGranted = true;
      _stopTracking();
      _startTracking();
      refreshViewport();
    } catch (error) {
      if (_disposed || generation != _locationGeneration) return;
      locationError = _message(error, '현재 위치를 확인하지 못했습니다. 다시 시도해 주세요.');
      if (error is LocationException) {
        needsLocationSettings =
            config.web ||
            error.reason == LocationFailure.deniedForever ||
            error.reason == LocationFailure.serviceDisabled;
      }
    } finally {
      if (!_disposed && generation == _locationGeneration) {
        locating = false;
        _emit();
      }
    }
  }

  void _startTracking() {
    if (!_foreground || !_locationGranted || _locationSubscription != null) {
      return;
    }
    final generation = ++_trackingGeneration;
    _locationSubscription = location.changes.listen(
      (point) {
        if (_disposed || !_foreground || generation != _trackingGeneration) {
          return;
        }
        myLocation = point;
        // Do not follow the user after they pan the map.
        _emit();
      },
      onError: (Object error) {
        if (!_disposed && _foreground && generation == _trackingGeneration) {
          _stopTracking();
          locationError = _message(
            error,
            '위치 갱신이 중단되었습니다. 현위치 버튼으로 다시 시도해 주세요.',
          );
          _emit();
        }
      },
      onDone: () {
        if (generation == _trackingGeneration) _locationSubscription = null;
      },
    );
  }

  void _stopTracking() {
    _trackingGeneration++;
    final previous = _locationSubscription;
    _locationSubscription = null;
    unawaited(previous?.cancel());
  }

  void setForeground(bool active) {
    final resumed = active && !_foreground;
    _foreground = active;
    if (active) {
      _startTracking();
      if (resumed && _started && !_disposed) {
        unawaited(loadHistory());
        refreshViewport();
      }
    } else {
      _locationGeneration++;
      locating = false;
      _stopTracking();
    }
  }

  Future<void> openLocationSettings() => location.openSettings();

  void dismissLocationError() {
    locationError = null;
    _emit();
  }

  Future<void> loadHistory({bool forceRefresh = false}) async {
    if (loadingHistory || _disposed) return;
    loadingHistory = true;
    historyError = null;
    _emit();
    try {
      final result = await historyRepository.load(forceRefresh: forceRefresh);
      if (_disposed) return;
      history = result;
      if (filter == null || _defaultDates) {
        final latest = HistoryFilter.latestTwoMonths(result.latestDate);
        filter = HistoryFilter(
          startDate: latest.startDate,
          endDate: latest.endDate,
          region: filter?.region,
        );
      }
      _applyFilter();
    } catch (error) {
      if (_disposed) return;
      historyError = _message(error, '경보 이력을 불러오지 못했습니다. 연결을 확인하고 다시 시도해 주세요.');
    } finally {
      if (!_disposed) {
        loadingHistory = false;
        _emit();
      }
    }
  }

  void setFilter(HistoryFilter value, {bool? useDefaultDates}) {
    if (useDefaultDates != null) {
      _defaultDates = useDefaultDates;
    } else if (filter != null &&
        (filter!.startDate != value.startDate ||
            filter!.endDate != value.endDate)) {
      _defaultDates = false;
    }
    filter = value;
    markerLimit = 60;
    _applyFilter();
    _emit();
  }

  void resetFilter() {
    if (history != null) {
      setFilter(
        HistoryFilter.latestTwoMonths(history!.latestDate),
        useDefaultDates: true,
      );
    }
  }

  void _applyFilter() {
    if (history == null || filter == null) return;
    filteredRecords = filter!.apply(history!.records);
    mapRecords = filter!.mapRecords(history!.records);
    unawaited(_resolveMarkers());
  }

  void loadMoreMarkers() {
    markerLimit += 60;
    unawaited(_resolveMarkers());
  }

  Future<void> retryMarkers() => _resolveMarkers();

  Future<void> _resolveMarkers() async {
    final generation = ++_geocodeGeneration;
    geocodeError = null;
    if (!config.placesEnabled) {
      geocoding = false;
      _emit();
      return;
    }
    final queue = mapRecords
        .take(markerLimit)
        .where((r) => !_addressCache.containsKey(r.address))
        .toList();
    var nextIndex = 0;
    geocoding = queue.isNotEmpty;
    _emit();
    Future<void> worker() async {
      while (!_disposed &&
          generation == _geocodeGeneration &&
          nextIndex < queue.length) {
        final record = queue[nextIndex++];
        try {
          final result = await places.resolveAddress(record.address);
          if (_disposed) return;
          _addressCache[record.address] = result;
          if (generation == _geocodeGeneration) _emit();
        } catch (error) {
          if (_disposed || generation != _geocodeGeneration) return;
          geocodeError = _message(
            error,
            '일부 주소를 지도에 표시하지 못했습니다. 이력 목록은 확인할 수 있습니다.',
          );
          // Stop this batch on network/auth failures instead of repeating it per address.
          nextIndex = queue.length;
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
    if (!_disposed && generation == _geocodeGeneration) {
      geocoding = false;
      _emit();
    }
  }

  GeoPoint? pointFor(WarningRecord record) => _addressCache[record.address];
  bool addressUnavailable(WarningRecord record) =>
      _addressCache.containsKey(record.address) &&
      _addressCache[record.address] == null;
  int get displayedHistoryMarkers => mapRecords
      .take(markerLimit)
      .where((r) => _addressCache[r.address] != null)
      .length;

  List<MapPin> get markers => [
    for (final mountain in mountains)
      MapPin(
        id: 'mountain:${mountain.id}',
        point: MapPoint(mountain.point.latitude, mountain.point.longitude),
        title: mountain.name,
        kind: 'mountain',
      ),
    for (final record in mapRecords.take(markerLimit))
      if (_addressCache[record.address] case final GeoPoint point)
        MapPin(
          id: 'history:${record.id}',
          point: MapPoint(point.latitude, point.longitude),
          title:
              '${record.town.isEmpty ? record.district : record.town} · ${record.date.month}/${record.date.day}',
          kind: 'history',
        ),
  ];

  Future<bool> showRecord(WarningRecord record) async {
    GeoPoint? point = _addressCache[record.address];
    if (point == null &&
        !_addressCache.containsKey(record.address) &&
        config.placesEnabled) {
      try {
        point = await places.resolveAddress(record.address);
        if (_disposed) return false;
        _addressCache[record.address] = point;
      } catch (error) {
        geocodeError = _message(error, '주소의 위치를 찾지 못했습니다.');
      }
    }
    if (point == null || _disposed) return false;
    final index = mapRecords.indexWhere((r) => r.address == record.address);
    if (index >= markerLimit) markerLimit = index + 1;
    center = point;
    cameraRevision++;
    refreshViewport();
    _emit();
    return true;
  }

  String _message(Object error, String fallback) =>
      error is DataException || error is LocationException
      ? error.toString()
      : fallback;

  @override
  void dispose() {
    _disposed = true;
    _viewportGeneration++;
    _geocodeGeneration++;
    _locationGeneration++;
    _debounce?.cancel();
    _stopTracking();
    super.dispose();
  }
}
