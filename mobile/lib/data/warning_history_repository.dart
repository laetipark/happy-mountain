import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:http/http.dart' as http;

import '../domain/contracts.dart';
import 'background_runner.dart';
import 'http_support.dart';
import 'warning_cache.dart';

export 'warning_cache.dart';

class WarningDownload {
  const WarningDownload(this.uri, this.modifiedAt);
  final Uri uri;
  final DateTime? modifiedAt;
}

WarningDownload findWarningDownload(String html) {
  final scripts = RegExp(
    r'''<script\b[^>]*\btype\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script\s*>''',
    caseSensitive: false,
  );
  WarningDownload? find(dynamic value) {
    if (value is List) {
      for (final child in value) {
        final match = find(child);
        if (match != null) return match;
      }
    } else if (value is Map) {
      final distributions = value['distribution'];
      for (final item
          in distributions is List ? distributions : [distributions]) {
        if (item is! Map) continue;
        final encoding = '${item['encodingFormat']}'.toLowerCase();
        if (encoding != 'csv' && encoding != 'text/csv') continue;
        final uri = Uri.tryParse('${item['contentUrl']}');
        if (uri == null || uri.host.isEmpty || uri.scheme != 'https') continue;
        return WarningDownload(
          uri,
          DateTime.tryParse('${value['dateModified']}'),
        );
      }
      for (final child in value.values) {
        final match = find(child);
        if (match != null) return match;
      }
    }
    return null;
  }

  for (final script in scripts.allMatches(html)) {
    try {
      final found = find(jsonDecode(script.group(1)!));
      if (found != null) return found;
    } on FormatException {
      continue;
    }
  }
  throw const DataException('공식 자료 페이지에서 CSV 다운로드 주소를 찾지 못했습니다.');
}

/// RFC 4180 style quoted values, doubled quotes, CRLF and quoted newlines.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  var quoteClosed = false;
  void endField() {
    row.add(field.toString());
    field = StringBuffer();
    quoteClosed = false;
  }

  void endRow() {
    endField();
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    row = [];
  }

  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
          quoteClosed = true;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"' && field.isEmpty && !quoteClosed) {
      quoted = true;
    } else if (char == ',') {
      endField();
    } else if (char == '\r' || char == '\n') {
      if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
        index++;
      }
      endRow();
    } else {
      field.write(char);
    }
  }
  if (quoted) throw const DataException('CSV에 닫히지 않은 따옴표가 있어 자료를 읽지 못했습니다.');
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

class ParsedWarnings {
  const ParsedWarnings(this.records, this.skippedRows);
  final List<WarningRecord> records;
  final int skippedRows;
}

DateTime? _parseIssuedAt(String text) {
  final compact = text.trim().replaceAll(RegExp(r'[-/: T]'), '');
  if (!RegExp(r'^\d{8}(\d{4}(\d{2})?)?$').hasMatch(compact)) return null;
  final year = int.parse(compact.substring(0, 4));
  final month = int.parse(compact.substring(4, 6));
  final day = int.parse(compact.substring(6, 8));
  final hour = compact.length >= 12 ? int.parse(compact.substring(8, 10)) : 0;
  final minute = compact.length >= 12
      ? int.parse(compact.substring(10, 12))
      : 0;
  final second = compact.length >= 14
      ? int.parse(compact.substring(12, 14))
      : 0;
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
  ).subtract(const Duration(hours: 9));
}

ParsedWarnings parseWarningBytes(Uint8List bytes) {
  String text;
  // The current source is CP949; also accept a future UTF-8 export losslessly.
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = cp949.decode(bytes);
  }
  final rows = parseCsv(text.replaceFirst(RegExp('^\uFEFF'), ''));
  if (rows.isEmpty) throw const DataException('경보 이력 CSV가 비어 있습니다.');
  final headers = <String, int>{
    for (var i = 0; i < rows.first.length; i++) rows.first[i].trim(): i,
  };
  const required = ['예보일시', '시도명', '시군구명', '읍면동명', '실효습도', '풍속', '등급'];
  if (!headers.keys.toSet().containsAll(required)) {
    throw const DataException('경보 이력 CSV의 필수 열 이름이 변경되었습니다.');
  }
  final records = <WarningRecord>[];
  var skipped = 0;
  for (final row in rows.skip(1)) {
    String get(String name) => row[headers[name]!].trim();
    if (row.length != rows.first.length) {
      skipped++;
      continue;
    }
    final issuedAt = _parseIssuedAt(get('예보일시'));
    if (issuedAt == null || get('시도명').isEmpty || get('등급').isEmpty) {
      skipped++;
      continue;
    }
    records.add(
      WarningRecord(
        issuedAt: issuedAt,
        region: get('시도명'),
        district: get('시군구명'),
        town: get('읍면동명'),
        grade: get('등급'),
        effectiveHumidity: double.tryParse(get('실효습도')),
        windSpeed: double.tryParse(get('풍속')),
      ),
    );
  }
  if (records.isEmpty) {
    throw const DataException('경보 이력 CSV에 읽을 수 있는 기록이 없습니다.');
  }
  records.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
  return ParsedWarnings(List.unmodifiable(records), skipped);
}

String encodeWarningCache(WarningDataset dataset) => jsonEncode({
  'version': 1,
  'fetchedAt': dataset.fetchedAt.toUtc().toIso8601String(),
  'modifiedAt': dataset.modifiedAt?.toIso8601String(),
  'skippedRows': dataset.skippedRows,
  'records': dataset.records
      .map(
        (r) => [
          r.issuedAt.toIso8601String(),
          r.region,
          r.district,
          r.town,
          r.grade,
          r.effectiveHumidity,
          r.windSpeed,
        ],
      )
      .toList(),
});

WarningDataset decodeWarningCache(String text) {
  final data = jsonDecode(text) as Map<String, dynamic>;
  if (data['version'] != 1) throw const FormatException('Unsupported cache');
  final records = (data['records'] as List).map((raw) {
    final row = raw as List;
    return WarningRecord(
      issuedAt: DateTime.parse(row[0] as String),
      region: row[1] as String,
      district: row[2] as String,
      town: row[3] as String,
      grade: row[4] as String,
      effectiveHumidity: (row[5] as num?)?.toDouble(),
      windSpeed: (row[6] as num?)?.toDouble(),
    );
  }).toList()..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
  if (records.isEmpty) throw const FormatException('Empty cache');
  return WarningDataset(
    records: List.unmodifiable(records),
    latestDate: records.first.date,
    fetchedAt: DateTime.parse(data['fetchedAt'] as String),
    modifiedAt: DateTime.tryParse('${data['modifiedAt']}'),
    skippedRows: data['skippedRows'] as int? ?? 0,
  );
}

class PublicWarningHistoryRepository implements WarningHistoryRepository {
  PublicWarningHistoryRepository({
    required this.client,
    required this.cache,
    this.gatewayOrigin,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final http.Client client;
  final WarningCache cache;
  final Uri? gatewayOrigin;
  final DateTime Function() clock;
  static final source = Uri.parse(
    'https://www.data.go.kr/data/15092027/fileData.do',
  );
  WarningDataset? _memory;
  Future<WarningDataset>? _inFlight;
  @override
  Future<WarningDataset> load({bool forceRefresh = false}) =>
      _inFlight ??= _load(forceRefresh).whenComplete(() => _inFlight = null);

  Future<WarningDataset> _load(bool forceRefresh) async {
    if (_memory == null) {
      try {
        final saved = await cache.read();
        if (saved != null) {
          _memory = await runBackground(() => decodeWarningCache(saved));
        }
      } catch (_) {
        /* A corrupt cache must not block a fresh download. */
      }
    }
    final now = clock().toUtc();
    if (!forceRefresh &&
        _memory != null &&
        !_memory!.isStale &&
        calendarDate(koreanTime(_memory!.fetchedAt)) ==
            calendarDate(koreanTime(now))) {
      return _memory!;
    }
    try {
      final download = await _download(forceRefresh: forceRefresh);
      final response = download.response;
      final bytes = response.bodyBytes;
      final parsed = await runBackground(() => parseWarningBytes(bytes));
      var result = WarningDataset(
        records: parsed.records,
        latestDate: parsed.records.first.date,
        fetchedAt: now,
        modifiedAt: download.modifiedAt,
        skippedRows: parsed.skippedRows,
      );
      try {
        final persisted = result;
        await cache.write(
          await runBackground(() => encodeWarningCache(persisted)),
        );
      } catch (_) {
        result = result.withWarning('새 자료를 불러왔지만 기기에 저장하지 못했습니다.');
      }
      _memory = result;
      return result;
    } catch (error) {
      final message = error is DataException
          ? error.message
          : '경보 이력을 읽지 못했습니다. 인터넷 연결과 자료 제공 상태를 확인해 주세요.';
      if (_memory != null) {
        _memory = _memory!.withWarning('새로고침 실패: $message 저장된 자료를 표시합니다.');
        return _memory!;
      }
      throw DataException(message);
    }
  }

  Future<({http.Response response, DateTime? modifiedAt})> _download({
    required bool forceRefresh,
  }) async {
    if (gatewayOrigin != null) {
      final response = await getResponse(
        client,
        gatewayEndpoint(
          gatewayOrigin!,
          '/api/history',
          forceRefresh ? {'forceRefresh': 'true'} : null,
        ),
        gatewayOrigin: gatewayOrigin,
      );
      return (
        response: response,
        modifiedAt: DateTime.tryParse(
          response.headers['x-data-modified-at'] ?? '',
        ),
      );
    }
    final page = await getResponse(client, source);
    final download = findWarningDownload(utf8.decode(page.bodyBytes));
    return (
      response: await getResponse(client, download.uri),
      modifiedAt: download.modifiedAt,
    );
  }
}
