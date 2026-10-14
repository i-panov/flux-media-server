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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            filesChannel(),
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> saveToDownloads(call, result)
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

        /// Канал сохранения файлов в Загрузки: имя задаётся из `main()`
        /// через `setFileChannelName` тем же способом.
        fun filesChannel() = "${BuildConfig.APPLICATION_ID}/files"

        const val NOTIFICATION_PERMISSION_REQUEST = 4711
        const val STORAGE_PERMISSION_REQUEST = 4712
    }

    /**
     * Копия готового файла в системные Загрузки без загрузки в память:
     * видео в гигабайты через Dart-байты не прогнать. Потоковое копирование
     * чанками по 1 МБ в обе стороны.
     *
     * API 29+: MediaStore (scoped storage, разрешений не нужно) —
     * файл виден в проводнике и галерее. Ниже: прямой путь в публичные
     * Загрузки с WRITE_EXTERNAL_STORAGE (запрашиваем здесь же).
     * Отложенный результат хранится в [pendingSaveResult]: разрешение —
     * асинхронное, дописываем файл уже после ответа пользователя.
     */
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveArgs: Map<*, *>? = null

    private fun saveToDownloads(
        call: MethodChannel.MethodCall,
        result: MethodChannel.Result,
    ) {
        val args = call.arguments as? Map<*, *>
        val sourcePath = args?.get("sourcePath") as? String
        val fileName = args?.get("fileName") as? String
        val mimeType = args?.get("mimeType") as? String ?: "application/octet-stream"
        if (sourcePath.isNullOrEmpty() || fileName.isNullOrEmpty()) {
            result.error("bad_args", "sourcePath/fileName обязательны", null)
            return
        }
        // Второй сейв, пока висит запрос разрешения по первому, затирает
        // pending-результат и вешает первый Future навсегда: отклоняем.
        // (Пересоздание Activity с висящим pending — тот же висяк, но
        // лечится только таймаутом на Dart-стороне; здесь минимум.)
        if (pendingSaveResult != null) {
            result.error("busy", "Дождитесь завершения сохранения", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                result.success(saveViaMediaStore(sourcePath, fileName, mimeType))
            } catch (e: Exception) {
                result.error("save_failed", e.message, null)
            }
            return
        }
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            try {
                result.success(saveViaLegacyPath(sourcePath, fileName))
            } catch (e: Exception) {
                result.error("save_failed", e.message, null)
            }
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingSaveResult = result
            pendingSaveArgs = args
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST,
            )
        } else {
            result.error("no_permission", "Нет доступа к хранилищу", null)
        }
    }

    private fun saveViaMediaStore(
        sourcePath: String,
        fileName: String,
        mimeType: String,
    ): String {
        // IS_PENDING прячет недописанный файл от проводника и галереи:
        // без него большой файл виден в Загрузках ещё во время копирования.
        val values = android.content.ContentValues().apply {
            put(
                android.provider.MediaStore.Downloads.DISPLAY_NAME,
                fileName,
            )
            put(
                android.provider.MediaStore.Downloads.MIME_TYPE,
                mimeType,
            )
            put(
                android.provider.MediaStore.Downloads.RELATIVE_PATH,
                android.os.Environment.DIRECTORY_DOWNLOADS,
            )
            put(
                android.provider.MediaStore.Downloads.IS_PENDING,
                1,
            )
        }
        val resolver = contentResolver
        val uri = resolver.insert(
            android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values,
        ) ?: throw java.io.IOException("MediaStore не вернул Uri")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                java.io.FileInputStream(sourcePath).use { `in` ->
                    copyStream(`in`, out)
                }
            } ?: throw java.io.IOException("Не открыт поток записи")
        } catch (e: Exception) {
            // Недописанный мусор не оставляем в Загрузках.
            resolver.delete(uri, null, null)
            throw e
        }
        val done = android.content.ContentValues().apply {
            put(
                android.provider.MediaStore.Downloads.IS_PENDING,
                0,
            )
        }
        resolver.update(uri, done, null, null)
        return fileName
    }

    private fun saveViaLegacyPath(sourcePath: String, fileName: String): String {
        val downloads = android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS,
        )
        if (!downloads.exists()) downloads.mkdirs()
        // Как MediaStore (он суффиксует дубли сам): молча не перезаписываем,
        // подбираем свободное имя «name (n).ext».
        val target = uniqueFile(downloads, fileName)
        java.io.FileInputStream(sourcePath).use { `in` ->
            java.io.FileOutputStream(target).use { out ->
                copyStream(`in`, out)
            }
        }
        return target.absolutePath
    }

    private fun uniqueFile(dir: java.io.File, fileName: String): java.io.File {
        var candidate = java.io.File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var n = 1
        while (true) {
            n++
            candidate = java.io.File(dir, "$stem ($n)$ext")
            if (!candidate.exists()) return candidate
        }
    }

    private fun copyStream(
        `in`: java.io.InputStream,
        out: java.io.OutputStream,
    ) {
        val buffer = ByteArray(1024 * 1024)
        while (true) {
            val read = `in`.read(buffer)
            if (read < 0) break
            out.write(buffer, 0, read)
        }
        out.flush()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST) return
        val result = pendingSaveResult
        val args = pendingSaveArgs
        pendingSaveResult = null
        pendingSaveArgs = null
        if (result == null || args == null) return
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            val sourcePath = args["sourcePath"] as? String
            val fileName = args["fileName"] as? String
            if (sourcePath.isNullOrEmpty() || fileName.isNullOrEmpty()) {
                result.error("bad_args", "sourcePath/fileName обязательны", null)
                return
            }
            try {
                result.success(saveViaLegacyPath(sourcePath, fileName))
            } catch (e: Exception) {
                result.error("save_failed", e.message, null)
            }
        } else {
            result.error("no_permission", "Нет доступа к хранилищу", null)
        }
    }
}
