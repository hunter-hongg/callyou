package com.callyou.callyou

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "callyou/call_reminder"
        private const val NOTIFICATION_REQUEST = 40129
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val context: Context = applicationContext
                when (call.method) {
                    "start" -> {
                        CallReminderService.start(context)
                        askForNotificationPermission()
                        result.success(true)
                    }
                    "setLoop" -> {
                        val files = call.argument<List<String>>("files") ?: emptyList()
                        CallReminderService.setLoop(context, files)
                        result.success(true)
                    }
                    "setStatus" -> {
                        CallReminderService.setStatus(
                            context,
                            call.argument<String>("text") ?: "",
                        )
                        result.success(true)
                    }
                    "stop" -> {
                        CallReminderService.stop(context)
                        result.success(true)
                    }
                    "isRunning" -> result.success(CallReminderService.isRunning())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android 13+ 不给通知权限就没有常驻通知，前台服务也会被拒；学生在前台
     * 登录学生端时顺手问一次，被拒也只是退回「前台可用、后台不提醒」。
     */
    private fun askForNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_REQUEST) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            CallReminderService.start(applicationContext)
        }
    }
}
