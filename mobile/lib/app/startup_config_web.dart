import 'package:http/http.dart' as http;

import '../data/http_support.dart';
import 'app_config.dart';

Future<AppConfig> loadAppConfig(http.Client client) async {
  final origin = Uri.parse(Uri.base.origin);
  return AppConfig.fromGateway(
    decodeObject(
      await getResponse(
        client,
        origin.resolve('/api/config'),
        gatewayOrigin: origin,
      ),
    ),
  );
}
