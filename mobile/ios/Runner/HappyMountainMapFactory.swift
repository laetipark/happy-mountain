import Flutter
import UIKit
import KakaoMapsSDK

/// Direct Flutter Platform View backed by KakaoMapsSDK 2.12.19.
final class HappyMountainMapFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        HappyMountainMapView(frame: frame, viewId: viewId, messenger: messenger,
                             parameters: args as? [String: Any] ?? [:])
    }
}

private final class HappyMountainMapView: NSObject, FlutterPlatformView,
    MapControllerDelegate, KakaoMapEventDelegate {
    private let eventForwarder = WeakMapEventForwarder()
    private let container: KMViewContainer
    private let channel: FlutterMethodChannel
    private let parameters: [String: Any]
    private let mapName = "happy-mountain-map"
    private let markersLayerId = "hm-markers"
    private let locationLayerId = "hm-location"
    private var controller: KMController?
    private var map: KakaoMap?
    private var markerLayer: LabelLayer?
    private var locationLayer: LabelLayer?
    private var initialized = false
    private var disposed = false
    private var markers: [[String: Any]] = []
    private var myLocation: MapPoint?
    private var target: MapPoint
    private var zoom: Int

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger,
         parameters: [String: Any]) {
        self.parameters = parameters
        container = KMViewContainer(frame: frame)
        channel = FlutterMethodChannel(name: "happy_mountain/map/\(viewId)",
                                       binaryMessenger: messenger)
        target = Self.coordinate(parameters) ?? MapPoint(longitude: 126.9780, latitude: 37.5665)
        zoom = min(21, max(6, (parameters["zoom"] as? NSNumber)?.intValue ?? 13))
        super.init()
        eventForwarder.owner = self
        container.backgroundColor = UIColor(red: 0.94, green: 0.96, blue: 0.93, alpha: 1)
        container.accessibilityLabel = "산과 경보 이력을 표시하는 카카오 지도"
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self, !self.disposed else {
                result(FlutterError(code: "disposed", message: "지도 화면이 종료되었습니다.", details: nil))
                return
            }
            self.handle(call, result: result)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(pause),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func view() -> UIView { container }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            start()
        case "moveCamera":
            guard let args = call.arguments as? [String: Any], let position = Self.coordinate(args) else {
                result(FlutterError(code: "invalid_coordinate", message: "올바른 지도 좌표가 필요합니다.", details: nil))
                return
            }
            target = position
            zoom = min(21, max(6, (args["zoom"] as? NSNumber)?.intValue ?? zoom))
            if let map = map {
                map.moveCamera(CameraUpdate.make(target: target, zoomLevel: zoom, mapView: map))
            }
        case "setMyLocation":
            if call.arguments == nil || call.arguments is NSNull {
                myLocation = nil
            } else if let args = call.arguments as? [String: Any], let position = Self.coordinate(args) {
                myLocation = position
            } else {
                result(FlutterError(code: "invalid_coordinate", message: "올바른 현재 위치가 필요합니다.", details: nil))
                return
            }
            drawLocation()
        case "replaceMarkers":
            guard let args = call.arguments as? [String: Any], let incoming = args["markers"] as? [[String: Any]] else {
                result(FlutterError(code: "invalid_markers", message: "표식 목록이 필요합니다.", details: nil))
                return
            }
            var ids = Set<String>()
            markers = incoming.filter { item in
                guard let id = item["id"] as? String, Self.coordinate(item) != nil else { return false }
                return ids.insert(id).inserted
            }
            drawMarkers()
        case "dispose":
            dispose()
        default:
            result(FlutterMethodNotImplemented)
            return
        }
        result(nil)
    }

    private func start() {
        guard !initialized, !disposed else { return }
        let key = (parameters["nativeKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            emit("onError", ["message": "카카오 지도 네이티브 앱 키를 설정해 주세요."])
            return
        }
        initialized = true
        SDKInitializer.InitSDK(appKey: key)
        let mapController = KMController(viewContainer: container)
        controller = mapController
        mapController.delegate = self
        guard mapController.prepareEngine() else {
            emit("onError", ["message": "지도 엔진을 준비하지 못했습니다. 지도 화면을 다시 열어 주세요."])
            return
        }
        if UIApplication.shared.applicationState == .active { mapController.activateEngine() }
    }

    func addViews() {
        guard !disposed else { return }
        controller?.addView(MapviewInfo(viewName: mapName, viewInfoName: "map",
                                       defaultPosition: target, defaultLevel: zoom))
    }

    func addViewSucceeded(_ viewName: String, viewInfoName: String) {
        guard !disposed, viewName == mapName,
              let map = controller?.getView(viewName) as? KakaoMap else { return }
        self.map = map
        // Some SDK releases retain eventDelegate. The proxy prevents a retain cycle
        // so Platform View removal still releases the engine without a Dart dispose.
        map.eventDelegate = eventForwarder
        containerDidResized(container.bounds.size)
        let manager = map.getLabelManager()
        markerLayer = manager.addLabelLayer(option: LabelLayerOptions(
            layerID: markersLayerId, competitionType: .none,
            competitionUnit: .symbolFirst, orderType: .rank, zOrder: 10000))
        locationLayer = manager.addLabelLayer(option: LabelLayerOptions(
            layerID: locationLayerId, competitionType: .none,
            competitionUnit: .symbolFirst, orderType: .rank, zOrder: 10001))
        for (kind, color) in [
            ("mountain", UIColor(red: 39/255, green: 111/255, blue: 189/255, alpha: 1)),
            ("history", UIColor(red: 201/255, green: 63/255, blue: 61/255, alpha: 1)),
            ("location", UIColor(red: 26/255, green: 130/255, blue: 104/255, alpha: 1))
        ] {
            let icon = PoiIconStyle(symbol: markerImage(color: color, location: kind == "location"),
                anchorPoint: CGPoint(x: 0.5, y: kind == "location" ? 0.5 : 1))
            let text = PoiTextStyle(textLineStyles: [PoiTextLineStyle(
                textStyle: TextStyle(fontSize: 12, fontColor: UIColor(red: 0.13, green: 0.18, blue: 0.15, alpha: 1),
                                     strokeThickness: 2, strokeColor: .white))])
            text.textLayouts = [.bottom]
            manager.addPoiStyle(PoiStyle(styleID: "hm-\(kind)", styles: [
                PerLevelPoiStyle(iconStyle: icon, textStyle: text, level: 0)
            ]))
        }
        drawMarkers()
        drawLocation()
        map.moveCamera(CameraUpdate.make(target: target, zoomLevel: zoom, mapView: map))
        emit("onReady", nil)
    }

    func addViewFailed(_ viewName: String, viewInfoName: String) {
        emit("onError", ["message": "지도 정보를 불러오지 못했습니다. 네트워크를 확인하고 다시 시도해 주세요."])
    }

    func authenticationFailed(_ errorCode: Int, desc: String) {
        // The raw description can include request data. Send only an actionable code.
        emit("onError", ["message": "카카오 지도 인증에 실패했습니다(\(errorCode)). 앱 키와 iOS 번들 ID 등록을 확인해 주세요."])
    }

    func containerDidResized(_ size: CGSize) {
        guard !disposed, size.width > 0, size.height > 0 else { return }
        map?.viewRect = CGRect(origin: .zero, size: size)
    }

    func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) {
        guard !disposed else { return }
        // getPosition takes a point in the view, not a normalized anchor.
        // Kakao's Roadview example uses viewRect.width/2 and height/2.
        target = kakaoMap.getPosition(CGPoint(x: kakaoMap.viewRect.width / 2,
                                             y: kakaoMap.viewRect.height / 2))
        zoom = kakaoMap.zoomLevel
        let coordinate = target.wgsCoord
        emit("onCameraIdle", ["latitude": coordinate.latitude, "longitude": coordinate.longitude])
    }

    func poiDidTapped(kakaoMap: KakaoMap, layerID: String, poiID: String, position: MapPoint) {
        if layerID == markersLayerId { emit("onMarkerTap", ["id": poiID]) }
    }

    private func drawMarkers() {
        guard !disposed, let layer = markerLayer else { return }
        layer.clearAllItems()
        for item in markers {
            guard let id = item["id"] as? String, let position = Self.coordinate(item) else { continue }
            let kind = item["kind"] as? String == "history" ? "history" : "mountain"
            let option = PoiOptions(styleID: "hm-\(kind)", poiID: id)
            option.clickable = true
            option.addText(PoiText(text: item["title"] as? String ?? "", styleIndex: 0))
            layer.addPoi(option: option, at: position)?.show()
        }
    }

    private func drawLocation() {
        guard !disposed, let layer = locationLayer else { return }
        layer.clearAllItems()
        guard let position = myLocation else { return }
        let option = PoiOptions(styleID: "hm-location", poiID: "hm-my-location")
        option.clickable = false
        option.addText(PoiText(text: "내 위치", styleIndex: 0))
        layer.addPoi(option: option, at: position)?.show()
    }

    @objc private func pause() { if !disposed { controller?.pauseEngine() } }

    @objc private func resume() {
        guard !disposed, let controller = controller, controller.isEnginePrepared else { return }
        controller.activateEngine()
    }

    private func emit(_ event: String, _ arguments: Any?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.disposed else { return }
            self.channel.invokeMethod(event, arguments: arguments)
        }
    }

    private func dispose() {
        guard !disposed else { return }
        disposed = true
        channel.setMethodCallHandler(nil)
        NotificationCenter.default.removeObserver(self)
        map?.eventDelegate = nil
        controller?.delegate = nil
        controller?.pauseEngine()
        controller?.resetEngine()
        map = nil
        markerLayer = nil
        locationLayer = nil
        controller = nil
        markers = []
    }

    deinit { dispose() }

    private static func coordinate(_ args: [String: Any]) -> MapPoint? {
        guard let latitude = (args["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (args["longitude"] as? NSNumber)?.doubleValue,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return MapPoint(longitude: longitude, latitude: latitude)
    }

    private func markerImage(color: UIColor, location: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // The SDK performs device-independent scaling itself.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: location ? 32 : 40), format: format)
        return renderer.image { _ in
            if !location {
                color.setFill()
                let tail = UIBezierPath()
                tail.move(to: CGPoint(x: 8, y: 23))
                tail.addLine(to: CGPoint(x: 16, y: 39))
                tail.addLine(to: CGPoint(x: 24, y: 23))
                tail.close()
                tail.fill()
            }
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 30, height: 30)).fill()
            color.setFill()
            let inset: CGFloat = location ? 6 : 4
            UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: 32 - 2 * inset, height: 32 - 2 * inset)).fill()
            UIColor.white.setFill()
            if location {
                UIBezierPath(ovalIn: CGRect(x: 13, y: 13, width: 6, height: 6)).fill()
            } else {
                let mountain = UIBezierPath()
                mountain.move(to: CGPoint(x: 9, y: 21))
                mountain.addLine(to: CGPoint(x: 16, y: 10))
                mountain.addLine(to: CGPoint(x: 23, y: 21))
                mountain.close()
                mountain.fill()
            }
        }
    }
}

private final class WeakMapEventForwarder: NSObject, KakaoMapEventDelegate {
    weak var owner: HappyMountainMapView?

    func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) {
        owner?.cameraDidStopped(kakaoMap: kakaoMap, by: by)
    }

    func poiDidTapped(kakaoMap: KakaoMap, layerID: String, poiID: String, position: MapPoint) {
        owner?.poiDidTapped(kakaoMap: kakaoMap, layerID: layerID, poiID: poiID, position: position)
    }
}
