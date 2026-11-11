package com.aurora.music.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.aurora.music.MainActivity
import com.aurora.music.R
import com.aurora.music.playback.PlaybackService
import java.io.File
import java.util.concurrent.Executors

/**
 * Home-screen (and, where the launcher allows it, lock-screen/keyguard) Now Playing widget.
 * Playback state is pushed in by [PlaybackService] through [push]; buttons talk to the same
 * Media3 session through a short-lived MediaController, so they work with the app closed.
 */
class NowPlayingWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle?) {
        render(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = when (intent.action) {
            ACTION_TOGGLE, ACTION_NEXT, ACTION_PREV -> intent.action
            else -> return
        }
        val pending = goAsync()
        try {
            val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
            val future = MediaController.Builder(context, token).buildAsync()
            future.addListener({
                try {
                    val c = future.get()
                    when (action) {
                        ACTION_TOGGLE -> if (c.isPlaying) c.pause() else if (c.mediaItemCount > 0) { c.prepare(); c.play() }
                        ACTION_NEXT -> c.seekToNext()
                        ACTION_PREV -> c.seekToPrevious()
                    }
                    c.release()
                } catch (t: Throwable) {
                    Log.w(TAG, "widget action failed", t)
                } finally {
                    pending.finish()
                }
            }, androidx.core.content.ContextCompat.getMainExecutor(context))
        } catch (t: Throwable) {
            Log.w(TAG, "widget action failed", t)
            pending.finish()
        }
    }

    companion object {
        private const val TAG = "AuroraWidget"
        const val ACTION_TOGGLE = "com.aurora.music.widget.TOGGLE"
        const val ACTION_NEXT = "com.aurora.music.widget.NEXT"
        const val ACTION_PREV = "com.aurora.music.widget.PREV"
        private const val PREFS = "aurora_widget"
        private val io = Executors.newSingleThreadExecutor()

        /** Called by the playback service whenever the item or play state changes. */
        fun push(context: Context, title: String, artist: String, playing: Boolean, art: Bitmap?, clearArt: Boolean = false) {
            val app = context.applicationContext
            try {
                app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putString("title", title).putString("artist", artist).putBoolean("playing", playing).apply()
                if (art != null) io.execute { saveArt(app, art); refreshAll(app) }
                else if (clearArt || title.isEmpty()) io.execute { artFile(app).delete(); blurFile(app).delete(); refreshAll(app) }
                else refreshAll(app)
            } catch (t: Throwable) {
                Log.w(TAG, "widget push failed", t)
            }
        }

        private fun artFile(c: Context) = File(c.cacheDir, "widget_art.png")

        private fun blurFile(c: Context) = File(c.cacheDir, "widget_blur.png")

        private fun saveArt(c: Context, bmp: Bitmap) {
            runCatching {
                val side = 256
                val scaled = if (bmp.width > side || bmp.height > side) Bitmap.createScaledBitmap(bmp, side, side, true) else bmp
                artFile(c).outputStream().use { scaled.compress(Bitmap.CompressFormat.PNG, 100, it) }
                // Frosted backdrop: shrink hard, then smooth back up. Cheap blur that RemoteViews can carry.
                val tiny = Bitmap.createScaledBitmap(bmp, 12, 12, true)
                val soft = Bitmap.createScaledBitmap(tiny, 96, 96, true)
                blurFile(c).outputStream().use { soft.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }

        private fun refreshAll(c: Context) {
            val m = AppWidgetManager.getInstance(c)
            val ids = m.getAppWidgetIds(ComponentName(c, NowPlayingWidget::class.java))
            ids.forEach { render(c, m, it) }
        }

        private fun render(c: Context, m: AppWidgetManager, id: Int) {
            try {
                val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val title = prefs.getString("title", null)?.takeIf { it.isNotEmpty() }
                val artist = prefs.getString("artist", "").orEmpty()
                val playing = prefs.getBoolean("playing", false)
                val minW = m.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
                val compact = minW < 180
                val v = RemoteViews(c.packageName, if (compact) R.layout.widget_now_playing_small else R.layout.widget_now_playing)

                v.setTextViewText(R.id.w_title, title ?: c.getString(R.string.widget_idle_title))
                v.setTextViewText(R.id.w_artist, if (title == null) c.getString(R.string.widget_idle_subtitle) else artist)
                v.setImageViewResource(R.id.w_play, if (playing) R.drawable.ic_w_pause else R.drawable.ic_w_play)

                val art = artFile(c).takeIf { it.exists() && title != null }
                    ?.let { runCatching { BitmapFactory.decodeFile(it.path) }.getOrNull() }
                if (art != null) v.setImageViewBitmap(R.id.w_art, art) else v.setImageViewResource(R.id.w_art, R.drawable.w_art_placeholder)
                val blur = blurFile(c).takeIf { it.exists() && title != null }
                    ?.let { runCatching { BitmapFactory.decodeFile(it.path) }.getOrNull() }
                if (blur != null) v.setImageViewBitmap(R.id.w_blur, blur) else v.setImageViewResource(R.id.w_blur, android.R.color.transparent)

                val open = PendingIntent.getActivity(
                    c, 0, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                // With nothing loaded, play opens the app (a broadcast cannot start an activity on Android 12+).
                v.setOnClickPendingIntent(R.id.w_play, if (title == null) open else action(c, ACTION_TOGGLE))
                if (!compact) {
                    v.setOnClickPendingIntent(R.id.w_next, action(c, ACTION_NEXT))
                    v.setOnClickPendingIntent(R.id.w_prev, action(c, ACTION_PREV))
                }
                v.setOnClickPendingIntent(R.id.w_root, open)
                m.updateAppWidget(id, v)
            } catch (t: Throwable) {
                Log.w(TAG, "widget render failed", t)
            }
        }

        private fun action(c: Context, a: String): PendingIntent = PendingIntent.getBroadcast(
            c, a.hashCode(), Intent(c, NowPlayingWidget::class.java).setAction(a),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
