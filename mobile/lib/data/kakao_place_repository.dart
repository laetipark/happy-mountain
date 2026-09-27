import 'dart:async';
import 'dart:collection';

import 'package:http/http.dart' as http;

import '../domain/contracts.dart';
import 'http_support.dart';

class KakaoPlaceRepository implements PlaceRepository {
  KakaoPlaceRepository({
    required this.client,
    this.restApiKey = '',
    this.gatewayOrigin,
  });
  final http.Client client;
  final String restApiKey;
  final Uri? gatewayOrigin;
  final _addressCache = <String, GeoPoint?>{};
  final _addressRequests = <String, Future<GeoPoint?>>{};
  final _permits = Queue<Completer<void>>();
  int _activeGeocodes = 0;

  Map<String, String> get _headers {
    if (gatewayOrigin != null) return const {};
    if (restApiKey.trim().isEmpty) {
      throw const DataException('카카오 REST API 키를 설정하면 산과 경보 위치를 볼 수 있습니다.');
    }
    return {'Authorization': 'KakaoAK ${restApiKey.trim()}'};
  }

  @override
  Future<List<MountainPlace>> searchMountains(GeoPoint center) async {
    final places = <String, MountainPlace>{};
    // Kakao Local exposes at most 45 documents for a keyword query (3 pages).
    for (var page = 1; page <= 3; page++) {
      final query = {
        'x': '${center.longitude}',
        'y': '${center.latitude}',
        'page': '$page',
      };
      final uri = gatewayOrigin != null
          ? gatewayEndpoint(gatewayOrigin!, '/api/places/mountains', query)
          : Uri.https('dapi.kakao.com', '/v2/local/search/keyword.json', {
              ...query,
              'query': '산',
              'category_group_code': 'AT4',
              'radius': '10000',
              'sort': 'distance',
              'size': '15',
            });
      final result = decodeObject(
        await getResponse(
          client,
          uri,
          headers: _headers,
          gatewayOrigin: gatewayOrigin,
        ),
      );
      final documents = result['documents'];
      if (documents is! List) throw const DataException('산 검색 응답 형식이 변경되었습니다.');
      for (final raw in documents) {
        if (raw is! Map) continue;
        final latitude = double.tryParse('${raw['y']}');
        final longitude = double.tryParse('${raw['x']}');
        final id = raw['id']?.toString();
        final name = raw['place_name']?.toString();
        if (latitude == null ||
            longitude == null ||
            id == null ||
            name == null) {
          continue;
        }
        places[id] = MountainPlace(
          id: id,
          name: name,
          address: '${raw['address_name'] ?? ''}',
          point: GeoPoint(latitude, longitude),
          distanceMeters: int.tryParse('${raw['distance']}'),
        );
      }
      if ((result['meta'] as Map?)?['is_end'] == true || documents.isEmpty) {
        break;
      }
    }
    return places.values.toList();
  }

  @override
  Future<GeoPoint?> resolveAddress(String address) {
    final normalized = address.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_addressCache.containsKey(normalized)) {
      return Future.value(_addressCache[normalized]);
    }
    return _addressRequests.putIfAbsent(
      normalized,
      () => _resolve(normalized).whenComplete(() {
        _addressRequests.remove(normalized);
      }),
    );
  }

  Future<GeoPoint?> _resolve(String address) async {
    if (_activeGeocodes >= 3) {
      final permit = Completer<void>();
      _permits.add(permit);
      await permit.future;
    } else {
      _activeGeocodes++;
    }
    try {
      final uri = gatewayOrigin != null
          ? gatewayEndpoint(gatewayOrigin!, '/api/places/address', {
              'query': address,
            })
          : Uri.https('dapi.kakao.com', '/v2/local/search/address.json', {
              'query': address,
              'size': '1',
            });
      final result = decodeObject(
        await getResponse(
          client,
          uri,
          headers: _headers,
          gatewayOrigin: gatewayOrigin,
        ),
      );
      final docs = result['documents'];
      if (docs is! List) throw const DataException('주소 검색 응답 형식이 변경되었습니다.');
      GeoPoint? point;
      if (docs.isNotEmpty && docs.first is Map) {
        final latitude = double.tryParse('${docs.first['y']}');
        final longitude = double.tryParse('${docs.first['x']}');
        if (latitude != null && longitude != null) {
          point = GeoPoint(latitude, longitude);
        }
      }
      _addressCache[address] = point;
      return point;
    } finally {
      if (_permits.isNotEmpty) {
        _permits.removeFirst().complete();
      } else {
        _activeGeocodes--;
      }
    }
  }
}
