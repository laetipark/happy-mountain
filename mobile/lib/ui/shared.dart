import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../domain/contracts.dart';

String formatDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
String formatTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    this.action,
    this.onAction,
  });
  final String message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xFFFFF4DB),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class DetailSheet extends StatelessWidget {
  const DetailSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => PointerInterceptor(
    intercepting: kIsWeb,
    child: SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void showWarningDetails(
  BuildContext context,
  WarningRecord record, {
  VoidCallback? onShowMap,
}) {
  final date = koreanTime(record.issuedAt);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DetailSheet(
      icon: Icons.history_rounded,
      title: record.address,
      children: [
        Text(
          '발령 등급  ${record.grade}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('발령 시각  ${formatDate(date)} ${formatTime(date)} (한국 시간)'),
        if (record.effectiveHumidity != null)
          Text('실효습도  ${record.effectiveHumidity}%'),
        if (record.windSpeed != null) Text('풍속  ${record.windSpeed} m/s'),
        if (record.canonicalRegion != record.region)
          Text('원본 지역명  ${record.region}'),
        const Text('공개 자료의 과거 발령 기록입니다. 현재 위험도를 나타내지 않습니다.'),
        if (onShowMap != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              onShowMap();
            },
            icon: const Icon(Icons.map_outlined),
            label: const Text('이 주소 지도에서 보기'),
          ),
      ],
    ),
  );
}
