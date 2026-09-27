package com.example.happy_mountain.mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "happy_mountain/map",
            HappyMountainMapFactory(this, flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
