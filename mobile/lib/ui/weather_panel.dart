import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import 'shared.dart';

class WeatherPanel extends StatefulWidget {
  const WeatherPanel({super.key, required this.controller});
  final AppController controller;
  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends State<WeatherPanel> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final weather = controller.weather;
    return Card(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      weather?.skyCode == 1
                          ? Icons.wb_sunny_outlined
                          : Icons.cloud_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '지도 중심 날씨',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            controller.loadingWeather
                                ? '날씨를 불러오는 중'
                                : weather == null
                                ? '날씨 정보 안내'
                                : '${weather.temperatureC.toStringAsFixed(1)}°  ${weather.skyLabel}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (controller.loadingWeather)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (controller.weatherError != null) ...[
                      Text(controller.weatherError!),
                      if (controller.config.weatherEnabled)
                        TextButton.icon(
                          onPressed: controller.refreshViewport,
                          icon: const Icon(Icons.refresh),
                          label: const Text('다시 시도'),
                        ),
                    ],
                    if (weather != null) ...[
                      const Divider(),
                      Wrap(
                        spacing: 20,
                        runSpacing: 12,
                        children: [
                          _metric(
                            context,
                            '기온',
                            '${weather.temperatureC.toStringAsFixed(1)} °C',
                          ),
                          _metric(
                            context,
                            '습도',
                            '${weather.humidityPercent.toStringAsFixed(0)} %',
                          ),
                          _metric(context, '하늘', weather.skyLabel),
                          _metric(context, '강수형태', weather.precipitationLabel),
                          _metric(
                            context,
                            '풍속',
                            '${weather.windSpeedMetersPerSecond.toStringAsFixed(1)} m/s',
                          ),
                          _metric(
                            context,
                            '풍향',
                            '${weather.windDirectionLabel} ${weather.windDirectionDegrees.toStringAsFixed(0)}°',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${formatDate(koreanTime(weather.forecastAt))} ${formatTime(koreanTime(weather.forecastAt))} 예보 · 한국 시간',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '기상청 ${formatTime(koreanTime(weather.baseTime))} 발표',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}
