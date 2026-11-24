package se.orbit.orbit_tv

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max

/**
 * Videospelare med Androids egen ExoPlayer. Videon går direkt till TV:ns videokrets
 * (samma väg som TV:ns inbyggda appar), i stället för att ritas via Flutter.
 * Styrs med fjärrkontrollen: vänster/höger = spola, OK = paus, ner = meny, Tillbaka = stäng.
 */
@OptIn(UnstableApi::class)
class PlayerActivity : Activity() {
    companion object {
        /** Skickar händelser (progress, fav) till Flutter-sidan. Sätts av MainActivity. */
        var events: ((String, Any?) -> Unit)? = null
        private const val ACCENT = 0xFF7C5CFF.toInt()
    }

    private lateinit var player: ExoPlayer
    private lateinit var playerView: PlayerView
    private val h = Handler(Looper.getMainLooper())

    private lateinit var topBar: LinearLayout
    private lateinit var bottomBar: LinearLayout
    private lateinit var progress: ProgressBar
    private lateinit var timeText: TextView
    private lateinit var stateText: TextView
    private lateinit var spinner: ProgressBar
    private lateinit var errorText: TextView
    private lateinit var nextCard: LinearLayout
    private lateinit var nextTime: TextView
    private lateinit var menuPanel: ScrollView
    private lateinit var menuList: LinearLayout

    private var live = false
    private var seekStep = 10
    private var speed = 1f
    private var hasNext = false
    private var nextDismissed = false
    private var hasFav = false
    private var isFav = false
    private var matchFps = true
    private var fpsDone = false
    private var uiVisible = true
    private var lastPoke = 0L
    private var menuLevel: String? = null
    private var seekTarget: Long? = null
    private var finished = false
    private var lastError: String? = null
    private var liveRetries = 0
    private var lastSave = 0L

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun num(k: String): Number? = @Suppress("DEPRECATION") (intent.extras?.get(k) as? Number)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemUi()

        val url = intent.getStringExtra("url") ?: ""
        live = intent.getBooleanExtra("live", false)
        seekStep = num("seekStep")?.toInt() ?: 10
        speed = num("speed")?.toFloat() ?: 1f
        hasNext = intent.getBooleanExtra("hasNext", false)
        hasFav = intent.getBooleanExtra("hasFav", false)
        isFav = intent.getBooleanExtra("isFav", false)
        matchFps = intent.getBooleanExtra("matchFps", true)
        val startMs = num("startMs")?.toLong() ?: 0L

        // ---------- Spelaren ----------
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.20 LibVLC/3.0.20")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(20000)
            .setReadTimeoutMs(20000)
        val load = DefaultLoadControl.Builder()
            .setBufferDurationsMs(20000, 60000, 1500, 3000)
            .build()
        val renderers = DefaultRenderersFactory(this).setEnableDecoderFallback(true)
        player = ExoPlayer.Builder(this, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(http))
            .setLoadControl(load)
            .build()

        val langs = intent.getStringArrayListExtra("subLangs") ?: arrayListOf()
        if (intent.getBooleanExtra("autoSubs", false) && langs.isNotEmpty()) {
            player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                .setPreferredTextLanguages(*langs.toTypedArray())
                .build()
        }

        // ---------- Vyer ----------
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        playerView = PlayerView(this).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
            setKeepContentOnPlayerReset(false)
            player = this@PlayerActivity.player
        }
        root.addView(playerView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        styleSubtitles()

        spinner = ProgressBar(this).apply { indeterminateTintList = ColorStateList.valueOf(Color.WHITE) }
        root.addView(spinner, FrameLayout.LayoutParams(dp(64), dp(64), Gravity.CENTER))

        errorText = TextView(this).apply {
            setTextColor(Color.WHITE); textSize = 22f; gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            background = round(0xDD000000.toInt(), 16)
            visibility = View.GONE
        }
        root.addView(errorText, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER).apply { setMargins(dp(48), dp(48), dp(48), dp(48)) })

        // Övre fält: titel
        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(48), dp(32), dp(48), dp(48))
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0xDD000000.toInt(), 0))
        }
        topBar.addView(label(intent.getStringExtra("title") ?: "", 28f, Color.WHITE, true))
        val sub = intent.getStringExtra("sub") ?: ""
        if (sub.isNotEmpty()) topBar.addView(label(sub, 20f, 0xB3FFFFFF.toInt(), false))
        root.addView(topBar, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.TOP))

        // Nedre fält: förlopp och tid
        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(48), dp(48), dp(48), dp(32))
            background = GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, intArrayOf(0xDD000000.toInt(), 0))
        }
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progressTintList = ColorStateList.valueOf(ACCENT)
            progressBackgroundTintList = ColorStateList.valueOf(0x40FFFFFF)
        }
        if (!live) bottomBar.addView(progress, LinearLayout.LayoutParams(MATCH_PARENT, dp(8)))
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        stateText = label(if (live) "LIVE" else "▶", 22f, if (live) 0xFFFF5252.toInt() else Color.WHITE, true)
        timeText = label("", 22f, Color.WHITE, false).apply { setPadding(dp(14), 0, 0, 0) }
        row.addView(stateText)
        row.addView(timeText, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        row.addView(label("▼ Meny", 16f, 0x99FFFFFF.toInt(), false))
        bottomBar.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(12) })
        root.addView(bottomBar, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM))

        // Kort för nästa avsnitt
        nextCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = GradientDrawable().apply { setColor(0xE6000000.toInt()); cornerRadius = dp(16).toFloat(); setStroke(dp(2), ACCENT) }
            visibility = View.GONE
        }
        val nh = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        nh.addView(label("⏭  Spela nästa avsnitt", 24f, Color.WHITE, true), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        nextTime = label("", 18f, 0xB3FFFFFF.toInt(), false)
        nh.addView(nextTime)
        nextCard.addView(nh)
        val nl = intent.getStringExtra("nextLabel") ?: ""
        if (nl.isNotEmpty()) nextCard.addView(label(nl, 18f, Color.WHITE, false).apply { maxLines = 2; setPadding(0, dp(6), 0, 0) })
        nextCard.addView(label("OK = spela nu   ▲ = dölj", 16f, 0x99FFFFFF.toInt(), false).apply { setPadding(0, dp(10), 0, 0) })
        root.addView(nextCard, FrameLayout.LayoutParams(dp(520), WRAP_CONTENT, Gravity.BOTTOM or Gravity.END).apply { setMargins(dp(48), dp(48), dp(48), dp(150)) })

        // Meny (undertexter, ljud, hastighet, favorit)
        menuList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(20), dp(20), dp(20)) }
        menuPanel = ScrollView(this).apply {
            background = round(0xE1000000.toInt(), 16)
            addView(menuList)
            visibility = View.GONE
        }
        root.addView(menuPanel, FrameLayout.LayoutParams(dp(420), WRAP_CONTENT, Gravity.END or Gravity.CENTER_VERTICAL).apply { setMargins(dp(32), dp(32), dp(32), dp(32)) })

        setContentView(root)

        // ---------- Händelser ----------
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                spinner.visibility = if (state == Player.STATE_BUFFERING || state == Player.STATE_IDLE && lastError == null) View.VISIBLE else View.GONE
                if (state == Player.STATE_READY) {
                    liveRetries = 0
                    if (errorText.visibility == View.VISIBLE) errorText.visibility = View.GONE
                }
                if (state == Player.STATE_ENDED && !live) finishWith("done")
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!live) stateText.text = if (isPlaying) "▶" else "❚❚"
                if (!isPlaying) poke()
            }

            override fun onTracksChanged(tracks: Tracks) {
                if (matchFps && !fpsDone) {
                    val fps = player.videoFormat?.frameRate ?: -1f
                    if (fps > 0) {
                        fpsDone = true
                        matchRefreshRate(fps)
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                if (live && error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                    player.seekToDefaultPosition()
                    player.prepare()
                    return
                }
                if (live && liveRetries < 3) {
                    liveRetries++
                    h.postDelayed({ if (!finished) { player.prepare(); player.play() } }, 2000)
                    return
                }
                val msg = "${error.errorCodeName}${error.cause?.message?.let { ": $it" } ?: ""}"
                lastError = msg
                spinner.visibility = View.GONE
                errorText.text = "Kunde inte spela upp:\n$msg\n\nFungerar det inte? Prova Videoläge \"mpv\" under Inställningar."
                errorText.visibility = View.VISIBLE
            }
        })

        val item = MediaItem.Builder().setUri(url).apply {
            if (url.contains(".m3u8", ignoreCase = true)) setMimeType(MimeTypes.APPLICATION_M3U8)
        }.build()
        if (startMs > 0 && !live) player.setMediaItem(item, startMs) else player.setMediaItem(item)
        if (!live && speed != 1f) player.setPlaybackSpeed(speed)
        player.playWhenReady = true
        player.prepare()

        poke()
        h.post(tick)
    }

    // ---------- Hjälpare för vyer ----------
    private fun label(t: String, size: Float, color: Int, bold: Boolean) = TextView(this).apply {
        text = t; textSize = size; setTextColor(color); maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun round(color: Int, r: Int) = GradientDrawable().apply { setColor(color); cornerRadius = dp(r).toFloat() }

    private fun styleSubtitles() {
        val size = num("subSize")?.toFloat() ?: 42f
        val yellow = intent.getBooleanExtra("subYellow", false)
        val bg = intent.getBooleanExtra("subBg", true)
        playerView.subtitleView?.apply {
            setApplyEmbeddedStyles(false)
            setApplyEmbeddedFontSizes(false)
            setStyle(
                CaptionStyleCompat(
                    if (yellow) 0xFFFFE94A.toInt() else Color.WHITE,
                    if (bg) 0xAA000000.toInt() else Color.TRANSPARENT,
                    Color.TRANSPARENT,
                    if (bg) CaptionStyleCompat.EDGE_TYPE_NONE else CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                    Color.BLACK,
                    Typeface.DEFAULT_BOLD,
                )
            )
            setFixedTextSize(TypedValue.COMPLEX_UNIT_DIP, size * 0.85f)
            setBottomPaddingFraction(0.07f)
        }
    }

    private fun hideSystemUi() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
    }

    /**
     * Ställer om TV:n till en bildfrekvens som passar filmen (t.ex. 24 eller 50 Hz),
     * så att rörelser inte rycker. Återställs automatiskt när spelaren stängs.
     */
    private fun matchRefreshRate(fps: Float) {
        if (Build.VERSION.SDK_INT < 23) return
        try {
            val disp = (if (Build.VERSION.SDK_INT >= 30) display else @Suppress("DEPRECATION") windowManager.defaultDisplay) ?: return
            val cur = disp.mode
            var best: android.view.Display.Mode? = null
            var bestScore = Float.MAX_VALUE
            for (m in disp.supportedModes) {
                if (m.physicalWidth != cur.physicalWidth || m.physicalHeight != cur.physicalHeight) continue
                for (k in 1..3) {
                    val diff = abs(m.refreshRate - fps * k)
                    if (diff < 0.06f * k) {
                        val score = k * 10f + diff
                        if (score < bestScore) { bestScore = score; best = m }
                        break
                    }
                }
            }
            val b = best ?: return
            if (b.modeId == cur.modeId) return
            window.attributes = window.attributes.also { it.preferredDisplayModeId = b.modeId }
        } catch (_: Exception) {
        }
    }

    // ---------- Uppdatering av fälten ----------
    private val tick = object : Runnable {
        override fun run() {
            if (finished) return
            update()
            h.postDelayed(this, 500)
        }
    }

    private fun fmt(ms: Long): String {
        val s = max(0L, ms / 1000)
        val hh = s / 3600
        val mm = (s % 3600) / 60
        val ss = s % 60
        return if (hh > 0) String.format(Locale.ROOT, "%d:%02d:%02d", hh, mm, ss) else String.format(Locale.ROOT, "%d:%02d", mm, ss)
    }

    private fun update() {
        val dur = player.duration
        val pos = seekTarget ?: player.currentPosition
        if (!live) {
            if (dur > 0 && dur != C.TIME_UNSET) {
                progress.progress = ((pos * 1000) / dur).toInt().coerceIn(0, 1000)
                timeText.text = fmt(pos) + " / " + fmt(dur) + (if (seekTarget != null) "   Spolar…" else "")
            } else {
                timeText.text = fmt(pos)
            }
        }
        // Dölj fälten efter 4 sekunder
        val show = menuLevel != null || !player.isPlaying || System.currentTimeMillis() - lastPoke < 4000
        if (show != uiVisible) {
            uiVisible = show
            val v = if (show) View.VISIBLE else View.GONE
            topBar.visibility = v
            bottomBar.visibility = v
        }
        nextCard.visibility = if (nextVisible()) View.VISIBLE else View.GONE
        if (nextCard.visibility == View.VISIBLE) nextTime.text = "${(dur - pos) / 1000} s"
        // Spara var man är var tionde sekund
        val now = System.currentTimeMillis()
        if (!live && now - lastSave > 10000 && dur > 0 && dur != C.TIME_UNSET && player.currentPosition > 5000) {
            lastSave = now
            events?.invoke("progress", mapOf("pos" to (player.currentPosition / 1000).toInt(), "dur" to (dur / 1000).toInt()))
        }
    }

    private fun nextVisible(): Boolean {
        if (!hasNext || nextDismissed || menuLevel != null || finished) return false
        val dur = player.duration
        if (dur == C.TIME_UNSET || dur < 5 * 60 * 1000) return false
        val remain = dur - player.currentPosition
        val win = if (dur > 20 * 60 * 1000) 90_000L else 30_000L
        return remain > 0 && remain <= win
    }

    private fun poke() {
        lastPoke = System.currentTimeMillis()
        if (::topBar.isInitialized) update()
    }

    // ---------- Spolning ----------
    private val commitSeek = Runnable {
        seekTarget?.let { player.seekTo(it) }
        seekTarget = null
        update()
    }

    private fun seekBy(sec: Int) {
        if (live) return
        val dur = player.duration
        var t = (seekTarget ?: player.currentPosition) + sec * 1000L
        if (t < 0) t = 0
        if (dur > 0 && dur != C.TIME_UNSET && t > dur) t = dur
        seekTarget = t
        poke()
        h.removeCallbacks(commitSeek)
        h.postDelayed(commitSeek, 600)
    }

    // ---------- Meny ----------
    private fun menuItem(t: String, selected: Boolean, onClick: () -> Unit) = TextView(this).apply {
        text = (if (selected) "✓  " else "     ") + t
        textSize = 20f
        setTextColor(Color.WHITE)
        setPadding(dp(16), dp(12), dp(16), dp(12))
        isFocusable = true
        isClickable = true
        background = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), round(ACCENT, 10))
            addState(intArrayOf(), round(if (selected) 0x33FFFFFF else 0, 10))
        }
        setOnClickListener { onClick() }
    }

    private fun trackLabel(f: androidx.media3.common.Format, n: Int): String {
        val parts = mutableListOf<String>()
        f.label?.takeIf { it.isNotBlank() }?.let { parts.add(it) }
        f.language?.takeIf { it.isNotBlank() && it != "und" }?.let {
            val name = Locale(it).getDisplayLanguage(Locale("sv"))
            if (parts.none { p -> p.equals(name, true) }) parts.add(name.replaceFirstChar { c -> c.uppercase() })
        }
        if (f.channelCount > 0 && f.sampleMimeType?.startsWith("audio") == true) parts.add(if (f.channelCount >= 6) "5.1" else if (f.channelCount == 2) "stereo" else "${f.channelCount} kan.")
        return if (parts.isEmpty()) "Spår $n" else parts.joinToString(" · ")
    }

    private fun selectTrack(type: Int, g: Tracks.Group?, i: Int) {
        val b = player.trackSelectionParameters.buildUpon()
        if (g == null) {
            b.setTrackTypeDisabled(type, true)
        } else {
            b.setTrackTypeDisabled(type, false).setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, i))
        }
        player.trackSelectionParameters = b.build()
    }

    private fun showMenu(level: String) {
        menuLevel = level
        menuList.removeAllViews()
        val items = mutableListOf<TextView>()
        var focus: TextView? = null
        val title: String
        when (level) {
            "subs", "audio" -> {
                val type = if (level == "subs") C.TRACK_TYPE_TEXT else C.TRACK_TYPE_AUDIO
                title = if (level == "subs") "Undertexter" else "Ljudspår"
                val groups = player.currentTracks.groups.filter { it.type == type }
                if (level == "subs") {
                    val off = groups.none { it.isSelected } || player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
                    val v = menuItem("Av", off) { selectTrack(type, null, 0); closeMenu() }
                    items.add(v)
                    if (off) focus = v
                }
                var n = 0
                for (g in groups) {
                    for (i in 0 until g.length) {
                        if (!g.isTrackSupported(i)) continue
                        n++
                        val sel = g.isTrackSelected(i)
                        val v = menuItem(trackLabel(g.getTrackFormat(i), n), sel) { selectTrack(type, g, i); closeMenu() }
                        items.add(v)
                        if (sel) focus = v
                    }
                }
                if (n == 0) items.add(label(if (level == "subs") "Inga undertexter hittades i filen." else "Inga ljudspår hittades.", 16f, 0xB3FFFFFF.toInt(), false).apply { setPadding(0, dp(8), 0, 0) })
            }
            "speed" -> {
                title = "Hastighet"
                for (r in listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)) {
                    val v = menuItem(speedLabel(r), r == speed) { speed = r; player.setPlaybackSpeed(r); closeMenu() }
                    items.add(v)
                    if (r == speed) focus = v
                }
            }
            else -> {
                title = "Meny"
                if (!live) {
                    items.add(menuItem("Undertexter", false) { showMenu("subs") })
                    items.add(menuItem("Ljudspår", false) { showMenu("audio") })
                    items.add(menuItem("Hastighet (${speedLabel(speed)})", false) { showMenu("speed") })
                } else {
                    items.add(menuItem("Ljudspår", false) { showMenu("audio") })
                }
                if (hasFav) items.add(menuItem(if (isFav) "Ta bort favorit" else "Lägg till favorit", false) {
                    isFav = !isFav
                    events?.invoke("fav", isFav)
                    showMenu("main")
                })
                items.add(menuItem("Stäng", false) { closeMenu() })
            }
        }
        menuList.addView(label(title, 24f, Color.WHITE, true).apply { setPadding(0, 0, 0, dp(12)) })
        for (v in items) menuList.addView(v, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(4) })
        menuPanel.visibility = View.VISIBLE
        update()
        (focus ?: items.firstOrNull { it.isFocusable })?.requestFocus()
    }

    private fun speedLabel(r: Float) = (if (r == r.toInt().toFloat()) r.toInt().toString() else r.toString().replace('.', ',')) + "×"

    private fun closeMenu() {
        menuLevel = null
        menuPanel.visibility = View.GONE
        playerView.requestFocus()
        poke()
    }

    // ---------- Fjärrkontrollen ----------
    override fun dispatchKeyEvent(e: KeyEvent): Boolean {
        val k = e.keyCode
        if (k == KeyEvent.KEYCODE_BACK || k == KeyEvent.KEYCODE_ESCAPE) {
            if (e.action == KeyEvent.ACTION_UP) {
                when {
                    menuLevel != null && menuLevel != "main" -> showMenu("main")
                    menuLevel != null -> closeMenu()
                    else -> finishWith("back")
                }
            }
            return true
        }
        if (menuLevel != null) return super.dispatchKeyEvent(e)
        if (k == KeyEvent.KEYCODE_VOLUME_UP || k == KeyEvent.KEYCODE_VOLUME_DOWN || k == KeyEvent.KEYCODE_VOLUME_MUTE) return super.dispatchKeyEvent(e)
        if (e.action != KeyEvent.ACTION_DOWN) return true
        val repeat = e.repeatCount > 0
        val ok = k == KeyEvent.KEYCODE_DPAD_CENTER || k == KeyEvent.KEYCODE_ENTER || k == KeyEvent.KEYCODE_NUMPAD_ENTER
        if (nextVisible()) {
            if (ok || k == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) { finishWith("next"); return true }
            if (k == KeyEvent.KEYCODE_DPAD_UP) { nextDismissed = true; update(); return true }
        }
        when (k) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_MEDIA_REWIND -> seekBy(if (repeat) -seekStep * 3 else -seekStep)
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> seekBy(if (repeat) seekStep * 3 else seekStep)
            KeyEvent.KEYCODE_DPAD_DOWN -> if (uiVisible && !repeat) showMenu("main") else poke()
            KeyEvent.KEYCODE_MENU -> showMenu("main")
            KeyEvent.KEYCODE_DPAD_UP -> poke()
            KeyEvent.KEYCODE_MEDIA_PLAY -> { player.play(); poke() }
            KeyEvent.KEYCODE_MEDIA_PAUSE -> { player.pause(); poke() }
            KeyEvent.KEYCODE_MEDIA_STOP -> finishWith("back")
            KeyEvent.KEYCODE_MEDIA_NEXT -> if (hasNext) finishWith("next")
            else -> if (ok || k == KeyEvent.KEYCODE_SPACE || k == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) {
                if (lastError != null) { lastError = null; errorText.visibility = View.GONE; player.prepare(); player.play() }
                else if (player.isPlaying) player.pause() else player.play()
                poke()
            } else return super.dispatchKeyEvent(e)
        }
        return true
    }

    // ---------- Avslut ----------
    private fun finishWith(action: String) {
        if (finished) return
        finished = true
        h.removeCallbacksAndMessages(null)
        val dur = player.duration
        val data = Intent().apply {
            putExtra("action", action)
            putExtra("pos", ((seekTarget ?: player.currentPosition) / 1000).toInt())
            putExtra("dur", if (dur == C.TIME_UNSET || dur < 0) 0 else (dur / 1000).toInt())
            lastError?.let { putExtra("error", it) }
        }
        setResult(RESULT_OK, data)
        try { player.stop() } catch (_: Exception) {}
        finish()
    }

    override fun onStop() {
        super.onStop()
        // Hem-knappen eller annan app: pausa och skicka tillbaka var man var
        if (!finished && ::player.isInitialized) {
            player.pause()
            val dur = player.duration
            if (!live && dur > 0 && dur != C.TIME_UNSET) events?.invoke("progress", mapOf("pos" to (player.currentPosition / 1000).toInt(), "dur" to (dur / 1000).toInt()))
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    override fun onDestroy() {
        h.removeCallbacksAndMessages(null)
        if (::player.isInitialized) player.release()
        super.onDestroy()
    }
}
