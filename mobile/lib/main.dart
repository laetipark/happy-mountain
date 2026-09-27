import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app/app_controller.dart';
import 'app/location_service.dart';
import 'app/startup_config_native.dart'
    if (dart.library.js_interop) 'app/startup_config_web.dart'
    as startup;
import 'data/kakao_place_repository.dart';
import 'data/kma_weather_repository.dart';
import 'data/warning_history_repository.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AppBootstrap());
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();
  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  final _client = http.Client();
  AppController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final config = await startup.loadAppConfig(_client);
      final origin = config.web ? Uri.parse(Uri.base.origin) : null;
      final cache = await createWarningCache();
      if (!mounted) return;
      setState(() {
        _controller = AppController(
          config: config,
          places: KakaoPlaceRepository(
            client: _client,
            restApiKey: config.kakaoRestKey,
            gatewayOrigin: origin,
          ),
          weatherRepository: KmaWeatherRepository(
            client: _client,
            serviceKey: config.weatherKey,
            gatewayOrigin: origin,
          ),
          historyRepository: PublicWarningHistoryRepository(
            client: _client,
            cache: cache,
            gatewayOrigin: origin,
          ),
          location: DeviceLocationService(),
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '앱 설정을 불러오지 못했습니다. 연결을 확인하고 다시 시도해 주세요.');
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) return HappyMountainApp(controller: controller);
    return MaterialApp(
      title: '산등성이',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF386A46),
        fontFamily: 'Environment',
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', width: 72, height: 72),
                const SizedBox(height: 24),
                if (_error == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('산등성이를 준비하고 있습니다'),
                ] else ...[
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('다시 시도')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
