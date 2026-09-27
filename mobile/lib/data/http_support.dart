import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/contracts.dart';

Future<http.Response> getResponse(
  http.Client client,
  Uri uri, {
  Map<String, String>? headers,
  Uri? gatewayOrigin,
}) async {
  final sameOrigin =
      gatewayOrigin != null &&
      uri.hasAuthority &&
      gatewayOrigin.hasAuthority &&
      const ['https', 'http'].contains(uri.scheme) &&
      const ['https', 'http'].contains(gatewayOrigin.scheme) &&
      uri.origin == gatewayOrigin.origin;
  if (gatewayOrigin != null && !sameOrigin) {
    throw const DataException('웹 API는 현재 사이트와 같은 주소에서만 사용할 수 있습니다.');
  }
  final localGateway =
      sameOrigin &&
      uri.scheme == 'http' &&
      const ['localhost', '127.0.0.1', '::1'].contains(uri.host) &&
      uri.path.startsWith('/api/');
  if (uri.scheme != 'https' && !localGateway) {
    throw const DataException('안전한 HTTPS 주소만 사용할 수 있습니다.');
  }
  try {
    final response = await client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const DataException('API 인증에 실패했습니다. 로컬 API 키와 서비스 등록을 확인해 주세요.');
    }
    if (response.statusCode == 429) {
      throw const DataException('요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요.');
    }
    if (response.statusCode != 200) {
      throw DataException(
        '서버에서 데이터를 받지 못했습니다 (${response.statusCode}). 다시 시도해 주세요.',
      );
    }
    return response;
  } on DataException {
    rethrow;
  } on TimeoutException {
    throw const DataException('서버 응답이 늦습니다. 연결을 확인하고 다시 시도해 주세요.');
  } catch (_) {
    throw const DataException('인터넷 연결을 확인하고 다시 시도해 주세요.');
  }
}

/// Fixed, same-origin gateway routes. Upstream addresses never come from a user.
Uri gatewayEndpoint(Uri origin, String path, [Map<String, String>? query]) {
  if (!origin.hasAuthority ||
      !const ['https', 'http'].contains(origin.scheme) ||
      origin.userInfo.isNotEmpty ||
      !path.startsWith('/api/')) {
    throw const DataException('웹 API 연결 주소가 올바르지 않습니다.');
  }
  return Uri.parse(origin.origin).replace(path: path, queryParameters: query);
}

Map<String, dynamic> decodeObject(http.Response response) {
  try {
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  } catch (_) {
    throw const DataException('서버 응답 형식이 올바르지 않습니다. API 설정과 서비스 상태를 확인해 주세요.');
  }
}
