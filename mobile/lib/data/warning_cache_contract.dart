abstract interface class WarningCache {
  Future<String?> read();
  Future<void> write(String value);
}
