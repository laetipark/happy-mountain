package com.example.happy_mountain.mobile

import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.KakaoMapSdk
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.MapView
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.LabelLayer
import com.kakao.vectormap.label.LabelLayerOptions
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelStyles
import com.kakao.vectormap.label.LabelTextBuilder
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** A direct bridge to Kakao Maps SDK v2; no WebView or third-party map plugin. */
class HappyMountainMapFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        HappyMountainMapView(activity, context, messenger, viewId, args as? Map<*, *> ?: emptyMap<Any, Any>())
}

private class HappyMountainMapView(
    private val activity: Activity,
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val parameters: Map<*, *>,
) : PlatformView, MethodChannel.MethodCallHandler, Application.ActivityLifecycleCallbacks {
    private val container = FrameLayout(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "happy_mountain/map/$viewId")
    private var mapView: MapView? = null
    private var map: KakaoMap? = null
    private var markerLayer: LabelLayer? = null
    private var locationLayer: LabelLayer? = null
    private val styles = mutableMapOf<String, LabelStyles>()
    private var initialized = false
    private var disposed = false
    private var paused = false
    private var markers: List<Map<*, *>> = emptyList()
    private var myLocation: LatLng? = null
    private var target = coordinate(parameters) ?: LatLng.from(37.5665, 126.9780)
    private var zoom = (parameters["zoom"] as? Number)?.toInt()?.coerceIn(6, 21) ?: 13

    init {
        container.setBackgroundColor(Color.rgb(239, 244, 238))
        container.contentDescription = "산과 경보 이력을 표시하는 카카오 지도"
        channel.setMethodCallHandler(this)
        activity.application.registerActivityLifecycleCallbacks(this)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("disposed", "지도 화면이 종료되었습니다.", null)
            return
        }
        try {
            when (call.method) {
                // Flutter installs its event listener before this handshake, so even
                // synchronous missing-key errors cannot disappear during view creation.
                "initialize" -> start()
                "moveCamera" -> {
                    val args = call.arguments as? Map<*, *>
                    target = coordinate(args) ?: throw IllegalArgumentException("올바른 지도 좌표가 필요합니다.")
                    zoom = (args?.get("zoom") as? Number)?.toInt()?.coerceIn(6, 21) ?: zoom
                    map?.moveCamera(CameraUpdateFactory.newCenterPosition(target, zoom))
                }
                "setMyLocation" -> {
                    myLocation = if (call.arguments == null) null else
                        coordinate(call.arguments as? Map<*, *>)
                            ?: throw IllegalArgumentException("올바른 현재 위치가 필요합니다.")
                    drawLocation()
                }
                "replaceMarkers" -> {
                    val args = call.arguments as? Map<*, *>
                    val incoming = args?.get("markers") as? List<*>
                        ?: throw IllegalArgumentException("표식 목록이 필요합니다.")
                    markers = incoming.mapNotNull { it as? Map<*, *> }
                        .filter { it["id"] is String && coordinate(it) != null }
                        .distinctBy { it["id"] }
                    drawMarkers()
                }
                "dispose" -> dispose()
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("map_error", error.message ?: "지도 요청을 처리하지 못했습니다.", null)
        }
    }

    private fun start() {
        if (initialized) return
        val nativeKey = (parameters["nativeKey"] as? String)?.trim().orEmpty()
        if (nativeKey.isEmpty()) {
            emit("onError", mapOf("message" to "카카오 지도 네이티브 앱 키를 설정해 주세요."))
            return
        }
        initialized = true
        KakaoMapSdk.init(activity.applicationContext, nativeKey)
        val nativeView = MapView(container.context)
        mapView = nativeView
        container.addView(nativeView, FrameLayout.LayoutParams(-1, -1))
        nativeView.start(object : MapLifeCycleCallback() {
            override fun onMapDestroy() {
                map = null
                markerLayer = null
                locationLayer = null
                styles.clear()
            }

            override fun onMapError(error: Exception) {
                // Never forward the raw SDK message; it may contain request credentials.
                emit("onError", mapOf("message" to
                    "카카오 지도를 열지 못했습니다. 네트워크, 앱 키, Android 패키지명과 서명 키 해시 등록을 확인해 주세요."))
            }
        }, object : KakaoMapReadyCallback() {
            override fun getPosition(): LatLng = target
            override fun getZoomLevel(): Int = zoom

            override fun onMapReady(kakaoMap: KakaoMap) {
                if (disposed) return
                map = kakaoMap
                markerLayer = kakaoMap.labelManager?.addLayer(LabelLayerOptions.from("hm-markers").setZOrder(10000))
                locationLayer = kakaoMap.labelManager?.addLayer(LabelLayerOptions.from("hm-location").setZOrder(10001))
                for ((kind, color) in mapOf("mountain" to Color.rgb(39, 111, 189), "history" to Color.rgb(201, 63, 61), "location" to Color.rgb(26, 130, 104))) {
                    val style = LabelStyle.from(markerBitmap(color, kind == "location"))
                        .setAnchorPoint(0.5f, if (kind == "location") 0.5f else 1.0f)
                        .setTextStyles(12, Color.rgb(33, 47, 38), 2, Color.WHITE)
                    val added = kakaoMap.labelManager?.addLabelStyles(LabelStyles.from("hm-$kind", style))
                    if (added != null) styles[kind] = added
                }
                kakaoMap.setOnCameraMoveEndListener { _, position, _ ->
                    target = position.position
                    zoom = position.zoomLevel
                    emit("onCameraIdle", coordinatePayload(target))
                }
                kakaoMap.setOnLabelClickListener { _, layer, label ->
                    if (layer.layerId == "hm-markers") {
                        emit("onMarkerTap", mapOf("id" to label.labelId))
                        true
                    } else {
                        false
                    }
                }
                drawMarkers()
                drawLocation()
                // A location fix can arrive while SDK authentication is still pending.
                kakaoMap.moveCamera(CameraUpdateFactory.newCenterPosition(target, zoom))
                if (paused) nativeView.pause() else nativeView.resume()
                emit("onReady", null)
            }
        })
        if (paused) nativeView.pause() else nativeView.resume()
    }

    private fun drawMarkers() {
        val layer = markerLayer ?: return
        layer.removeAll()
        markers.forEach { marker ->
            val kind = if (marker["kind"] == "history") "history" else "mountain"
            val style = styles[kind] ?: return@forEach
            val point = coordinate(marker) ?: return@forEach
            layer.addLabel(LabelOptions.from(marker["id"] as String, point)
                .setStyles(style).setTexts(LabelTextBuilder().setTexts((marker["title"] as? String).orEmpty()))
                .setClickable(true))
        }
    }

    private fun drawLocation() {
        val layer = locationLayer ?: return
        layer.removeAll()
        val point = myLocation ?: return
        val style = styles["location"] ?: return
        layer.addLabel(LabelOptions.from("hm-my-location", point).setStyles(style)
            .setTexts(LabelTextBuilder().setTexts("내 위치")).setClickable(false))
    }

    private fun emit(event: String, arguments: Any?) {
        mainHandler.post { if (!disposed) channel.invokeMethod(event, arguments) }
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        activity.application.unregisterActivityLifecycleCallbacks(this)
        mapView?.pause()
        mapView?.finish()
        container.removeAllViews()
        mapView = null
        map = null
        markerLayer = null
        locationLayer = null
        styles.clear()
        markers = emptyList()
    }

    override fun onActivityPaused(current: Activity) {
        if (current === activity && !disposed) {
            paused = true
            mapView?.pause()
        }
    }

    override fun onActivityResumed(current: Activity) {
        if (current === activity && !disposed) {
            paused = false
            mapView?.resume()
        }
    }

    override fun onActivityDestroyed(current: Activity) { if (current === activity) dispose() }
    override fun onActivityCreated(current: Activity, state: Bundle?) = Unit
    override fun onActivityStarted(current: Activity) = Unit
    override fun onActivityStopped(current: Activity) = Unit
    override fun onActivitySaveInstanceState(current: Activity, state: Bundle) = Unit

    private fun coordinate(args: Map<*, *>?): LatLng? {
        val lat = (args?.get("latitude") as? Number)?.toDouble() ?: return null
        val lng = (args?.get("longitude") as? Number)?.toDouble() ?: return null
        if (!lat.isFinite() || !lng.isFinite() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return null
        return LatLng.from(lat, lng)
    }

    private fun coordinatePayload(point: LatLng) = mapOf("latitude" to point.latitude, "longitude" to point.longitude)

    private fun markerBitmap(color: Int, location: Boolean): Bitmap {
        // SDK applies its dp scaling. These programmatic markers need no asset licensing.
        val bitmap = Bitmap.createBitmap(32, if (location) 32 else 40, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        if (!location) {
            paint.color = color
            val tail = Path().apply { moveTo(8f, 23f); lineTo(16f, 39f); lineTo(24f, 23f); close() }
            canvas.drawPath(tail, paint)
        }
        paint.color = Color.WHITE
        canvas.drawCircle(16f, 16f, 15f, paint)
        paint.color = color
        canvas.drawCircle(16f, 16f, if (location) 10f else 12f, paint)
        paint.color = Color.WHITE
        if (location) {
            canvas.drawCircle(16f, 16f, 3f, paint)
        } else {
            val mountain = Path().apply { moveTo(9f, 21f); lineTo(16f, 10f); lineTo(23f, 21f); close() }
            canvas.drawPath(mountain, paint)
        }
        return bitmap
    }
}
