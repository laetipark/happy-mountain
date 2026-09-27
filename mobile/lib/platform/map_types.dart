import 'package:flutter/material.dart';

class MapPoint {
  const MapPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  Map<String, double> toMap() => {'latitude': latitude, 'longitude': longitude};
}

class MapPin {
  const MapPin({
    required this.id,
    required this.point,
    required this.title,
    required this.kind,
  });
  final String id;
  final MapPoint point;
  final String title;
  final String kind;

  Map<String, Object> toMap() => {
    'id': id,
    ...point.toMap(),
    'title': title,
    'kind': kind,
  };
}

class MapUnavailable extends StatelessWidget {
  const MapUnavailable({
    super.key,
    required this.message,
    required this.detail,
    this.onRetry,
  });
  final String message;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFEDF3E9),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terrain_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('지도 다시 연결'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
