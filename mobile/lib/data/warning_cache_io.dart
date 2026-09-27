import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'warning_cache_contract.dart';

Future<WarningCache> createWarningCache() async =>
    FileWarningCache(await getApplicationSupportDirectory());

/// Preserve the existing file name/schema so upgrading keeps offline history.
class FileWarningCache implements WarningCache {
  FileWarningCache(this.directory);
  final Directory directory;
  File get _file =>
      File('${directory.path}${Platform.pathSeparator}warning-history-v1.json');
  @override
  Future<String?> read() async =>
      await _file.exists() ? _file.readAsString() : null;
  @override
  Future<void> write(String value) async {
    await directory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(_file.path);
  }
}
