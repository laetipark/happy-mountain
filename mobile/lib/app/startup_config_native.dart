import 'package:http/http.dart' as http;

import 'app_config.dart';

Future<AppConfig> loadAppConfig(http.Client client) async => const AppConfig(
  kakaoNativeKey: String.fromEnvironment('KAKAO_NATIVE_APP_KEY'),
  kakaoRestKey: String.fromEnvironment('KAKAO_REST_API_KEY'),
  weatherKey: String.fromEnvironment('WEATHER_API_KEY'),
);
