package com.quickcapture.vn
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import android.net.Uri
import android.provider.Settings
import android.content.IntentFilter
class MainActivity: FlutterActivity() {
    private val CHANNEL = "quick_capture"
    private val SCREEN_RECORD_REQUEST_CODE = 1000
    private var projectionManager: MediaProjectionManager? = null
    private var methodChannel: MethodChannel? = null
    private val videoSavedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.quickcapture.vn.VIDEO_SAVED") {
                // Gửi lệnh yêu cầu Flutter load lại danh sách ngay lập tức
                methodChannel?.invokeMethod("onVideoSaved", null)
            }
        }
    }
    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        val filter = IntentFilter("com.quickcapture.vn.VIDEO_SAVED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(videoSavedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(videoSavedReceiver, filter)
        }

        methodChannel?.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("QuickCapturePrefs", Context.MODE_PRIVATE)

            when (call.method) {
                "startRecord" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                        startActivity(intent)
                        result.success("Vui lòng cấp quyền 'Hiển thị trên ứng dụng khác' rồi bấm lại.")
                    } else {
                        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        val captureIntent = projectionManager?.createScreenCaptureIntent()
                        startActivityForResult(captureIntent, SCREEN_RECORD_REQUEST_CODE)
                        result.success("Hãy chọn 'Bắt đầu truyền phát'...")
                    }
                }
                "getVideoList" -> {
                    val directory = getExternalFilesDir(Environment.DIRECTORY_MOVIES)
                    val files = directory?.listFiles { file -> file.extension == "mp4" }
                        ?.sortedByDescending { it.lastModified() }
                        ?.map { it.absolutePath } ?: emptyList()
                    result.success(files)
                }
                "saveSpecificVideo" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val success = saveVideoToGallery(path)
                        if (success) result.success("Thành công")
                        else result.success("Lỗi: Không thể lưu video")
                    } else {
                        result.success("Lỗi: Đường dẫn không hợp lệ")
                    }
                }
                "deleteVideo" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val file = File(path)
                        if (file.exists() && file.delete()) result.success(true)
                        else result.success(false)
                    } else {
                        result.success(false)
                    }
                }
                "checkNewVideoStatus" -> {
                    val hasNew = prefs.getBoolean("hasNewVideo", false)
                    if (hasNew) prefs.edit().putBoolean("hasNewVideo", false).apply()
                    result.success(hasNew)
                }
                "isRecording" -> result.success(prefs.getBoolean("isRecordingActive", false))
                "stopRecord" -> {
                    val stopIntent = Intent(this, RecordingService::class.java).apply {
                        action = "STOP_RECORDING"
                    }
                    startService(stopIntent)
                    result.success("ANDROID_STOPPED")
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        unregisterReceiver(videoSavedReceiver)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_RECORD_REQUEST_CODE) {
            val prefs = getSharedPreferences("QuickCapturePrefs", Context.MODE_PRIVATE)

            if (resultCode == Activity.RESULT_OK && data != null) {
                // Người dùng ĐỒNG Ý quay
                prefs.edit().putBoolean("isRecordingActive", true).apply()

                val serviceIntent = Intent(this, RecordingService::class.java).apply {
                    putExtra("code", resultCode)
                    putExtra("data", data)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }

                // 🚀 THÊM DÒNG NÀY: Báo cho Flutter đổi màu nút thành "DỪNG GHI HÌNH" ngay lập tức
                methodChannel?.invokeMethod("onRecordingStarted", null)

            } else {
                // Người dùng bấm HỦY hoặc tắt hộp thoại
                prefs.edit().putBoolean("isRecordingActive", false)
                    .putBoolean("hasNewVideo", false).apply()

                // 🚀 THÊM DÒNG NÀY: Báo cho Flutter reset nút về "Sẵn sàng"
                methodChannel?.invokeMethod("onRecordingStopped", null)
            }
        }
    }

    private fun saveVideoToGallery(filePath: String): Boolean {
        try {
            val file = File(filePath)
            if (!file.exists()) return false

            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/QuickCapture")
                }
            }

            val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            uri?.let {
                contentResolver.openOutputStream(it).use { outputStream ->
                    FileInputStream(file).use { inputStream ->
                        inputStream.copyTo(outputStream!!)
                    }
                }
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
}