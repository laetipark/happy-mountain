import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import '../platform/kakao_map.dart';
import 'history_tab.dart';
import 'shared.dart';
import 'weather_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  bool _foreground = true;
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.initialize();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.setForeground(true);
      setState(() => _foreground = true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      controller.setForeground(false);
      setState(() => _foreground = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _showRecordOnMap(WarningRecord record) async {
    final found = await controller.showRecord(record);
    if (!mounted) return;
    if (found) {
      setState(() => _tab = 0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !controller.config.placesEnabled
                ? '장소 연결 설정 후 지도에서 주소를 확인할 수 있습니다.'
                : '이 주소의 좌표를 찾지 못했습니다. 경보 기록은 목록에 유지됩니다.',
          ),
        ),
      );
    }
  }

  void _selectMarker(String id) {
    for (final mountain in controller.mountains) {
      if (id == 'mountain:${mountain.id}') {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) => DetailSheet(
            icon: Icons.terrain_rounded,
            title: mountain.name,
            children: [
              Text(mountain.address.isEmpty ? '주소 정보 없음' : mountain.address),
              if (mountain.distanceMeters != null)
                Text(
                  '지도 중심에서 ${(mountain.distanceMeters! / 1000).toStringAsFixed(1)} km',
                ),
            ],
          ),
        );
        return;
      }
    }
    for (final record in controller.mapRecords) {
      if (id == 'history:${record.id}') {
        showWarningDetails(context, record);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final wide =
          controller.config.web && MediaQuery.sizeOf(context).width >= 1024;
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 36,
                height: 36,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  '산등성이',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '앱 안내',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (context) => const DetailSheet(
                  icon: Icons.info_outline,
                  title: '산을 살피는 작은 습관',
                  children: [
                    Text(
                      '지도 중심 10 km 안의 산과 기상청 예보, 공개된 산불위험 예보 발령 이력을 함께 확인합니다.',
                    ),
                    Text('경보 이력은 과거 발령 자료이며 실시간 산불위험이나 현재 산불 발생 현황을 뜻하지 않습니다.'),
                    Text('날씨는 한국 표준시 기준입니다. 경보 이력의 지역과 기간 필터는 지도 표식에도 적용됩니다.'),
                    Text('자료 제공: 카카오맵 · 기상청 · 공공데이터포털'),
                  ],
                ),
              ),
              icon: const Icon(Icons.info_outline_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: wide
              ? Row(
                  key: const ValueKey('desktop-layout'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildMap(context)),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 400,
                      child: HistoryTab(
                        controller: controller,
                        onShowMap: _showRecordOnMap,
                      ),
                    ),
                  ],
                )
              : _tab == 0
              ? _buildMap(context)
              : HistoryTab(controller: controller, onShowMap: _showRecordOnMap),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map_rounded),
                    label: '지도',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_rounded),
                    selectedIcon: Icon(Icons.history_rounded),
                    label: '경보 이력',
                  ),
                ],
              ),
      );
    },
  );

  void _openLocationHelp() {
    if (!controller.config.web) {
      unawaited(controller.openLocationSettings());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const DetailSheet(
        icon: Icons.location_on_outlined,
        title: '브라우저 위치 권한',
        children: [
          Text('주소창 옆 사이트 설정에서 위치 권한을 허용한 뒤 현위치 버튼을 다시 눌러 주세요.'),
          Text('기기의 위치 서비스도 켜져 있어야 합니다. 위치를 공유하지 않아도 지도를 직접 이동할 수 있습니다.'),
          Text('위치 기능은 HTTPS 사이트 또는 이 기기의 localhost 주소에서 사용할 수 있습니다.'),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context) => Column(
    children: [
      if (controller.locationError != null)
        NoticeBanner(
          message: controller.locationError!,
          action: controller.needsLocationSettings
              ? (controller.config.web ? '권한 안내' : '설정')
              : '닫기',
          onAction: controller.needsLocationSettings
              ? _openLocationHelp
              : controller.dismissLocationError,
        ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: _foreground
                    ? KakaoMap(
                        nativeKey: controller.config.kakaoNativeKey,
                        javascriptKey: controller.config.kakaoJavascriptKey,
                        interactionEnabled:
                            ModalRoute.isCurrentOf(context) ?? true,
                        center: MapPoint(
                          controller.center.latitude,
                          controller.center.longitude,
                        ),
                        cameraRevision: controller.cameraRevision,
                        myLocation: controller.myLocation == null
                            ? null
                            : MapPoint(
                                controller.myLocation!.latitude,
                                controller.myLocation!.longitude,
                              ),
                        markers: controller.markers,
                        onCameraIdle: (point) => controller.cameraIdle(
                          GeoPoint(point.latitude, point.longitude),
                        ),
                        onMarkerTap: _selectMarker,
                      )
                    : const ColoredBox(color: Color(0xFFEDF3E9)),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .42,
                  ),
                  child: PointerInterceptor(
                    intercepting: kIsWeb,
                    child: WeatherPanel(controller: controller),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: FloatingActionButton.small(
                    heroTag: 'location',
                    tooltip: '내 위치로 이동',
                    onPressed: controller.locating ? null : controller.locate,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    child: controller.locating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          onTap: () => _showMapSummary(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                if (controller.loadingMountains || controller.geocoding)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.terrain_outlined, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    controller.mountainError != null
                        ? '주변 산 검색 안내 · 경보 표식 ${controller.displayedHistoryMarkers}곳'
                        : '반경 10 km · 산 ${controller.mountains.length}곳 · 경보 이력 ${controller.displayedHistoryMarkers}곳',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_up_rounded),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  void _showMapSummary(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => DetailSheet(
          icon: Icons.layers_outlined,
          title: '지도에 표시한 정보',
          children: [
            Text('산 · 지도 중심 반경 10 km, ${controller.mountains.length}곳'),
            if (controller.mountainError != null)
              Text(controller.mountainError!),
            if (controller.mountainError == null &&
                !controller.loadingMountains &&
                controller.mountains.isEmpty)
              const Text('이 주변에는 검색된 산이 없습니다. 지도를 이동해 보세요.'),
            OutlinedButton.icon(
              onPressed: controller.refreshViewport,
              icon: const Icon(Icons.refresh),
              label: const Text('주변 산·날씨 새로고침'),
            ),
            const Divider(),
            Text(
              '경보 이력 · ${controller.displayedHistoryMarkers}곳 / 주소 ${controller.mapRecords.length}곳',
            ),
            if (controller.filter != null)
              Text(
                '${formatDate(controller.filter!.startDate)} ~ ${formatDate(controller.filter!.endDate)} · ${controller.filter!.region ?? '전체 지역'}',
              ),
            const Text('같은 주소의 가장 최근 기록을 표시합니다. 과거 발령 이력이며 현재 위험도를 뜻하지 않습니다.'),
            if (!controller.config.placesEnabled)
              const Text('장소 연결을 설정하면 경보 주소가 지도에 표시됩니다.'),
            if (controller.geocodeError != null)
              NoticeBanner(
                message: controller.geocodeError!,
                action: '재시도',
                onAction: controller.retryMarkers,
              ),
            if (controller.geocoding) const LinearProgressIndicator(),
            if (controller.markerLimit < controller.mapRecords.length &&
                controller.config.placesEnabled)
              OutlinedButton(
                onPressed: controller.geocoding
                    ? null
                    : controller.loadMoreMarkers,
                child: const Text('다음 60곳 지도에 표시'),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _tab = 1);
              },
              child: const Text('경보 이력에서 기간·지역 변경'),
            ),
          ],
        ),
      ),
    );
  }
}
