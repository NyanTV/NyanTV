// android/app/src/main/kotlin/com/mukatos/nyantv/MainActivity.kt
package com.mukatos.nyantv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app/architecture"
    private val PLATFORM_CHANNEL = "app.nyantv/platform"
    private val WATCH_NEXT_CHANNEL = "com.nyantv/tv_watch_next"

    private lateinit var watchNextHelper: TvWatchNextHelper

    // FIX 2: Gecachte Engine nur verwenden, wenn sie wirklich existiert.
    //         Wird die App kalt via Watch-Next-Karte gestartet, läuft
    //         SplashActivity nicht → kein pre-warmed Engine → null zurückgeben,
    //         damit FlutterActivity selbst eine neue Engine erzeugt.
    override fun getCachedEngineId(): String? {
        return if (FlutterEngineCache.getInstance().contains("nyantv_engine")) {
            "nyantv_engine"
        } else {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        watchNextHelper = TvWatchNextHelper(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentArchitecture" -> {
                    val architecture = getCurrentArchitecture()
                    result.success(architecture)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getUIMode" -> {
                    val uiMode = getUIMode()
                    result.success(uiMode)
                }
                "isTV" -> {
                    val isTV = checkIfTV()
                    result.success(isTV)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_NEXT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWatchNext" -> {
                    val data = call.arguments as? Map<String, Any>
                    if (data != null) {
                        watchNextHelper.updateWatchNext(data)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Invalid arguments", null)
                    }
                }
                "removeFromWatchNext" -> {
                    val mediaId = call.argument<String>("mediaId")
                    if (mediaId != null) {
                        watchNextHelper.removeFromWatchNext(mediaId)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing mediaId", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getCurrentArchitecture(): String {
        return try {
            val primaryAbi = Build.SUPPORTED_ABIS?.firstOrNull()
            if (primaryAbi != null) {
                when {
                    primaryAbi.contains("arm64") || primaryAbi.contains("v8a") -> "arm64"
                    primaryAbi.contains("arm") || primaryAbi.contains("v7a") -> "arm32"
                    primaryAbi.contains("x86_64") -> "x86_64"
                    primaryAbi.contains("x86") -> "x86"
                    else -> primaryAbi
                }
            } else {
                getSystemProperty("ro.product.cpu.abi") ?: "unknown"
            }
        } catch (e: Exception) {
            e.printStackTrace()
            "unknown"
        }
    }

    private fun getSystemProperty(property: String): String? {
        return try {
            val process = Runtime.getRuntime().exec("getprop $property")
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val result = reader.readLine()
            reader.close()
            process.waitFor()
            result
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getUIMode(): String {
        return try {
            val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            when (uiModeManager?.currentModeType) {
                Configuration.UI_MODE_TYPE_TELEVISION -> "television"
                Configuration.UI_MODE_TYPE_DESK -> "desk"
                Configuration.UI_MODE_TYPE_CAR -> "car"
                Configuration.UI_MODE_TYPE_WATCH -> "watch"
                Configuration.UI_MODE_TYPE_VR_HEADSET -> "vr"
                else -> "normal"
            }
        } catch (e: Exception) {
            e.printStackTrace()
            "normal"
        }
    }

    private fun checkIfTV(): Boolean {
        return try {
            val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            val isTV = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
            val hasLeanback = packageManager.hasSystemFeature("android.software.leanback")
            val isTouchscreen = packageManager.hasSystemFeature("android.hardware.touchscreen")
            isTV || (hasLeanback && !isTouchscreen)
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}