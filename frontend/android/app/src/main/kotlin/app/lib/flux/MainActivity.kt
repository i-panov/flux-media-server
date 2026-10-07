package app.lib.flux

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannel(),
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" ->
                    result.success(requestNotificationPermission())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android 13+ требует runtime-разрешения на показ уведомлений: без него
     * foreground service не может показать уведомление с медиакнопками, и
     * системный плеер выглядит пропавшим.
     *
     * Возвращает `true` только если разрешение уже выдано. Если диалог
     * показан — `null`: результата ещё нет, и выдавать за него отказ
     * вводило бы в заблуждение. Dart-сторона значение игнорирует.
     *
     * Используем только framework API — androidx.core в зависимостях нет.
     */
    private fun requestNotificationPermission(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
        return null
    }

    private companion object {
        /// Имя канала выводится из ID приложения, а не хардкодится:
        /// Dart-сторона собирает его так же из packageName.
        fun notificationChannel() = "${BuildConfig.APPLICATION_ID}/notifications"

        const val NOTIFICATION_PERMISSION_REQUEST = 4711
    }
}
