/// Runtime capabilities allow the browser to use a gateway without its secrets.
class AppCapabilities {
  const AppCapabilities({
    required this.placesEnabled,
    required this.weatherEnabled,
  });
  final bool placesEnabled;
  final bool weatherEnabled;
}

/// Native and web loaders are conditionally imported to keep secrets out of JS.
class AppConfig {
  const AppConfig({
    this.kakaoNativeKey = '',
    this.kakaoRestKey = '',
    this.weatherKey = '',
    this.kakaoJavascriptKey = '',
    this.web = false,
    this.capabilities,
  });

  factory AppConfig.fromGateway(Map<String, dynamic> json) {
    if (json['kakaoJavascriptKey'] is! String ||
        json['placesEnabled'] is! bool ||
        json['weatherEnabled'] is! bool) {
      throw const FormatException('웹 설정 응답 형식이 올바르지 않습니다.');
    }
    return AppConfig(
      web: true,
      kakaoNativeKey: '',
      kakaoRestKey: '',
      weatherKey: '',
      kakaoJavascriptKey: json['kakaoJavascriptKey'] as String,
      capabilities: AppCapabilities(
        placesEnabled: json['placesEnabled'] as bool,
        weatherEnabled: json['weatherEnabled'] as bool,
      ),
    );
  }

  final String kakaoNativeKey;
  final String kakaoRestKey;
  final String weatherKey;
  final String kakaoJavascriptKey;
  final bool web;
  final AppCapabilities? capabilities;
  bool get placesEnabled =>
      capabilities?.placesEnabled ?? kakaoRestKey.isNotEmpty;
  bool get weatherEnabled =>
      capabilities?.weatherEnabled ?? weatherKey.isNotEmpty;
}
