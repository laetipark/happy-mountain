import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import 'shared.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({
    super.key,
    required this.controller,
    required this.onShowMap,
  });
  final AppController controller;
  final ValueChanged<WarningRecord> onShowMap;

  Future<void> _selectDates(BuildContext context) async {
    final history = controller.history;
    final filter = controller.filter;
    if (history == null || filter == null) return;
    var earliest = history.latestDate;
    for (final record in history.records) {
      if (record.date.isBefore(earliest)) earliest = record.date;
    }
    if (filter.startDate.isBefore(earliest)) earliest = filter.startDate;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: earliest,
      lastDate: history.latestDate.isAfter(filter.endDate)
          ? history.latestDate
          : filter.endDate,
      initialDateRange: DateTimeRange(
        start: filter.startDate,
        end: filter.endDate,
      ),
      helpText: '경보 이력 조회 기간',
      saveText: '적용',
    );
    if (selected != null) {
      controller.setFilter(
        HistoryFilter(
          startDate: selected.start,
          endDate: selected.end,
          region: filter.region,
        ),
        useDefaultDates: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    final filter = controller.filter;
    final records = controller.filteredRecords;
    return RefreshIndicator(
      onRefresh: () => controller.loadHistory(forceRefresh: true),
      child: CustomScrollView(
        key: const PageStorageKey('warning-history'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '산불위험 경보 이력',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '공개된 과거 발령 기록을 살펴보세요.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '실시간 위험정보가 아닙니다.',
                    style: TextStyle(
                      color: Color(0xFF815B27),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (history != null && filter != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '자료 최신일  ${formatDate(history.latestDate)}',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '가져온 시각  ${formatDate(koreanTime(history.fetchedAt))} ${formatTime(koreanTime(history.fetchedAt))}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '조회 기간',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: () => _selectDates(context),
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text(
                                '${formatDate(filter.startDate)} ~ ${formatDate(filter.endDate)}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: '지역',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: filter.region ?? '',
                                  items: [
                                    const DropdownMenuItem(
                                      value: '',
                                      child: Text('전체 지역'),
                                    ),
                                    for (final region in ({
                                      ...history.regions,
                                      if (filter.region != null) filter.region!,
                                    }.toList()..sort()))
                                      DropdownMenuItem(
                                        value: region,
                                        child: Text(region),
                                      ),
                                  ],
                                  onChanged: (value) => controller.setFilter(
                                    HistoryFilter(
                                      startDate: filter.startDate,
                                      endDate: filter.endDate,
                                      region: value,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: controller.resetFilter,
                              child: const Text('자료 최신일 기준 두 달로 초기화'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (history.refreshWarning != null) ...[
                      const SizedBox(height: 12),
                      NoticeBanner(
                        message: history.refreshWarning!,
                        action: '재시도',
                        onAction: () =>
                            controller.loadHistory(forceRefresh: true),
                      ),
                    ],
                    if (history.skippedRows > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '형식을 확인할 수 없는 ${history.skippedRows}개 행을 제외했습니다.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          '발령 기록 ${records.length}건',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextButton.icon(
                          onPressed: controller.loadingHistory
                              ? null
                              : () =>
                                    controller.loadHistory(forceRefresh: true),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('자료 새로고침'),
                        ),
                      ],
                    ),
                    Text(
                      '선택한 기간·지역이 지도에도 적용됩니다.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (controller.loadingHistory)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: LinearProgressIndicator(),
                    ),
                  if (controller.historyError != null) ...[
                    const SizedBox(height: 16),
                    NoticeBanner(
                      message: controller.historyError!,
                      action: '다시 시도',
                      onAction: () =>
                          controller.loadHistory(forceRefresh: true),
                    ),
                  ],
                  if (history != null &&
                      records.isEmpty &&
                      !controller.loadingHistory)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Column(
                        children: [
                          const Icon(Icons.manage_search_outlined, size: 40),
                          const SizedBox(height: 12),
                          const Text(
                            '선택한 기간·지역의 발령 기록이 없습니다.',
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: controller.resetFilter,
                            child: const Text('필터 초기화'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => showWarningDetails(
                        context,
                        record,
                        onShowMap: () => onShowMap(record),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5E9D3),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    record.grade,
                                    style: const TextStyle(
                                      color: Color(0xFF73531F),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatDate(record.date),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              record.address,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              controller.addressUnavailable(record)
                                  ? '좌표를 찾지 못함 · 발령 상세 보기'
                                  : '발령 상세 보기',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
