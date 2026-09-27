import 'warning_cache_contract.dart';

Future<WarningCache> createWarningCache() async => _UnsupportedWarningCache();

class _UnsupportedWarningCache implements WarningCache {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async =>
      throw UnsupportedError('Persistent storage unavailable');
}
