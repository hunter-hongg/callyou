package com.callyou.callyou

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.File

/**
 * 学生端退到后台时的前台服务：一条常驻通知 + 呼叫语音的循环播报。
 *
 * 通知让进程保持前台优先级，Dart 侧每 2 秒的轮询才不会被系统挂起；语音本身
 * 也在这里播，因为应用一旦不可见，Flutter 那边的音频随时可能被掐掉。
 */
class CallReminderService : Service() {

    companion object {
        private const val CHANNEL_ID = "callyou_call"
        private const val NOTIFICATION_ID = 40128

        /// ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        private const val TYPE_MEDIA_PLAYBACK = 128

        const val ACTION_START = "com.callyou.callyou.action.START"
        const val ACTION_SET_LOOP = "com.callyou.callyou.action.SET_LOOP"
        const val ACTION_SET_STATUS = "com.callyou.callyou.action.SET_STATUS"
        const val ACTION_STOP = "com.callyou.callyou.action.STOP"
        const val EXTRA_FILES = "files"
        const val EXTRA_TEXT = "text"

        private const val DEFAULT_STATUS = "正在等待新呼叫"

        @Volatile
        private var instance: CallReminderService? = null

        /** 服务没起来时这些调用只是空转，调用方不需要区分。 */
        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, CallReminderService::class.java).setAction(ACTION_START),
            )
        }

        fun setLoop(context: Context, files: List<String>) {
            forward(context, ACTION_SET_LOOP, files)
        }

        fun setStatus(context: Context, text: String) {
            forward(context, ACTION_SET_STATUS, emptyList(), text)
        }

        fun stop(context: Context) {
            forward(context, ACTION_STOP, emptyList())
        }

        fun isRunning(): Boolean = instance != null

        private fun forward(
            context: Context,
            action: String,
            files: List<String>,
            text: String? = null,
        ) {
            if (instance == null) return
            val intent = Intent(context, CallReminderService::class.java)
                .setAction(action)
                .putStringArrayListExtra(EXTRA_FILES, ArrayList(files))
                .putExtra(EXTRA_TEXT, text)
            context.startService(intent)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var audioThread: HandlerThread? = null
    private var audioHandler: Handler? = null
    private var player: MediaPlayer? = null
    private var loopFiles: List<String> = emptyList()
    private var cursor = 0
    private var looping = false
    private var statusText = DEFAULT_STATUS

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SET_LOOP -> {
                val files = intent.getStringArrayListExtra(EXTRA_FILES) ?: arrayListOf()
                audio().post { applyLoop(files.toList()) }
            }
            ACTION_SET_STATUS -> {
                statusText = intent.getStringExtra(EXTRA_TEXT) ?: DEFAULT_STATUS
                mainHandler.post { showNotification() }
            }
            ACTION_STOP -> {
                audio().post { stopLoop() }
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            else -> goForeground()
        }
        return START_STICKY
    }

    private fun goForeground() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { goForeground() }
            return
        }
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "课堂呼叫",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "学生端待回应的呼叫与语音提醒" },
        )
    }

    private fun buildNotification(): Notification {
        val tapIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("课堂呼叫提醒")
            .setContentText(statusText)
            .setContentIntent(tapIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
    }

    private fun showNotification() {
        if (!notificationsAllowed()) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun notificationsAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun audio(): Handler {
        audioHandler?.let { return it }
        val thread = HandlerThread("call-reminder-audio").apply { start() }
        audioThread = thread
        return Handler(thread.looper).also { audioHandler = it }
    }

    /** 在音频线程上执行：内容等价时什么都不做，重设会打断正在念的半句。 */
    private fun applyLoop(files: List<String>) {
        if (files == loopFiles) return
        loopFiles = files
        cursor = 0
        releasePlayer()
        looping = files.isNotEmpty()
        if (looping) playCurrent()
    }

    private fun playCurrent() {
        if (!looping || loopFiles.isEmpty()) {
            looping = false
            return
        }
        // 逐段试起：某一段坏掉就换下一段，一轮下来全不起来就彻底停下，
        // 免得在「失败 → 游标回绕 → 又失败」里死循环。
        var attempts = 0
        while (looping && attempts < loopFiles.size) {
            val path = loopFiles[cursor % loopFiles.size]
            cursor += 1
            if (!File(path).exists()) {
                attempts += 1
                continue
            }
            if (startPlayback(path)) return
            attempts += 1
        }
        looping = false
        releasePlayer()
    }

    private fun startPlayback(path: String): Boolean {
        val media = MediaPlayer()
        player = media
        return try {
            media.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            media.setDataSource(path)
            media.setOnCompletionListener {
                releasePlayer()
                if (looping) playCurrent()
            }
            media.setOnErrorListener { _, _, _ ->
                releasePlayer()
                looping = false
                true
            }
            media.prepare()
            media.start()
            true
        } catch (error: Exception) {
            releasePlayer()
            false
        }
    }

    private fun stopLoop() {
        looping = false
        loopFiles = emptyList()
        releasePlayer()
    }

    private fun releasePlayer() {
        player?.let {
            it.setOnCompletionListener(null)
            it.setOnErrorListener(null)
            runCatching { it.stop() }
            it.release()
        }
        player = null
    }

    override fun onDestroy() {
        instance = null
        audio().post { stopLoop() }
        audioThread?.quitSafely()
        audioThread = null
        audioHandler = null
        super.onDestroy()
    }
}
