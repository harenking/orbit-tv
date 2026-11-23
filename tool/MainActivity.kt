package se.orbit.orbit_tv

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Ger appen Androids egen förklaring till varför den senast stängdes (minne, krasch, ANR …). */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orbit/exit").setMethodCallHandler { call, result ->
            if (call.method != "lastExits") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < 30) {
                result.success(emptyList<Any>())
                return@setMethodCallHandler
            }
            try {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val list = am.getHistoricalProcessExitReasons(packageName, 0, 6).map { x ->
                    var trace: String? = null
                    if (x.reason == ApplicationExitInfo.REASON_ANR || x.reason == ApplicationExitInfo.REASON_CRASH) {
                        try {
                            trace = x.traceInputStream?.bufferedReader()?.use { it.readText().take(3000) }
                        } catch (err: Exception) {
                            trace = null
                        }
                    }
                    mapOf(
                        "reason" to x.reason,
                        "status" to x.status,
                        "desc" to (x.description ?: ""),
                        "time" to x.timestamp,
                        "pss" to x.pss,
                        "rss" to x.rss,
                        "trace" to trace,
                    )
                }
                result.success(list)
            } catch (err: Exception) {
                result.error("exit", err.toString(), null)
            }
        }
    }
}
