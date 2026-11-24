package se.orbit.orbit_tv

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Ger appen Androids egen förklaring till varför den senast stängdes (minne, krasch, ANR …). */
class MainActivity : FlutterActivity() {
    private val reqPlayer = 4711
    private var playerResult: MethodChannel.Result? = null
    private var playerChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Androids egen videospelare (ExoPlayer) i en egen skärm
        playerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orbit/player").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                playerResult?.success(mapOf("action" to "back", "pos" to 0, "dur" to 0))
                playerResult = result
                val i = Intent(this, PlayerActivity::class.java)
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                for ((k, v) in args) {
                    val key = k.toString()
                    when (v) {
                        is String -> i.putExtra(key, v)
                        is Boolean -> i.putExtra(key, v)
                        is Int -> i.putExtra(key, v)
                        is Long -> i.putExtra(key, v)
                        is Double -> i.putExtra(key, v)
                        is List<*> -> i.putStringArrayListExtra(key, ArrayList(v.map { it.toString() }))
                    }
                }
                PlayerActivity.events = { name, data -> runOnUiThread { playerChannel?.invokeMethod(name, data) } }
                try {
                    startActivityForResult(i, reqPlayer)
                } catch (err: Exception) {
                    playerResult = null
                    result.error("player", err.toString(), null)
                }
            }
        }
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
                    } else if (x.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                        // Inbyggda krascher ger en binär "tombstone". Plocka ut de läsbara raderna
                        // (signal, bibliotek och funktionsnamn) så att det syns var kraschen skedde.
                        try {
                            val bytes = x.traceInputStream?.use { it.readBytes() }
                            if (bytes != null) {
                                val sb = StringBuilder()
                                val cur = StringBuilder()
                                for (b in bytes) {
                                    val c = b.toInt() and 0xff
                                    if (c in 32..126) {
                                        cur.append(c.toChar())
                                    } else {
                                        if (cur.length >= 6) sb.append(cur).append('\n')
                                        cur.setLength(0)
                                    }
                                    if (sb.length > 6000) break
                                }
                                if (cur.length >= 6) sb.append(cur)
                                trace = sb.toString().lines()
                                    .filter { it.contains(".so") || it.contains("SIG") || it.contains("signal") || it.contains("Abort") || it.contains("Cause") }
                                    .distinct()
                                    .take(25)
                                    .joinToString("\n")
                                    .take(3000)
                            }
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqPlayer) return
        val r = playerResult ?: return
        playerResult = null
        r.success(
            mapOf(
                "action" to (data?.getStringExtra("action") ?: "back"),
                "pos" to (data?.getIntExtra("pos", 0) ?: 0),
                "dur" to (data?.getIntExtra("dur", 0) ?: 0),
                "error" to data?.getStringExtra("error"),
            )
        )
    }
}
