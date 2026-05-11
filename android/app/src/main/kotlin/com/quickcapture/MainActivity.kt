package com.quickcapture.vn

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "quick_capture"
    private val SCREEN_RECORD_REQUEST_CODE = 1000
    private val RECORD_AUDIO_REQUEST_CODE = 1001 // Mã request cho Micro

    private var projectionManager: MediaProjectionManager? = null
    private var methodChannel: MethodChannel? = null

    // Lưu lại trạng thái từ Flutter gửi xuống
    private var pendingQuality: String = "720p"
    private var pendingAudioEnabled: Boolean = true
    private var pendingResult: MethodChannel.Result? = null // Lưu result để trả về sau khi xin quyền

    private val videoSavedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.quickcapture.vn.VIDEO_SAVED") {
                context?.getSharedPreferences("QuickCapturePrefs", Context.MODE_PRIVATE)
                    ?.edit()?.putBoolean("hasNewVideo", false)?.apply()
                methodChannel?.invokeMethod("onVideoSaved", null)
            }
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        val prefs = getSharedPreferences("QuickCapturePrefs", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("hasNewVideo", false).apply()

        val filter = IntentFilter("com.quickcapture.vn.VIDEO_SAVED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(videoSavedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(videoSavedReceiver, filter)
        }

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecord" -> {
                    pendingQuality = call.argument<String>("quality") ?: "720p"
                    pendingAudioEnabled = call.argument<Boolean>("isAudioEnabled") ?: true
                    pendingResult = result // Lưu lại result

                    // 1. KIỂM TRA QUYỀN MICRO NẾU CÓ BẬT THU ÂM
                    if (pendingAudioEnabled && ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), RECORD_AUDIO_REQUEST_CODE)
                        // Hàm onRequestPermissionsResult bên dưới sẽ lo phần còn lại
                    } else {
                        // Đã có quyền Micro hoặc không thu âm -> Đi tiếp
                        startScreenCaptureFlow()
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

    // 2. TÁCH LUỒNG MỞ GIAO DIỆN QUAY THÀNH HÀM RIÊNG
    private fun startScreenCaptureFlow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            startActivity(intent)
            pendingResult?.success("Vui lòng cấp quyền 'Hiển thị trên ứng dụng khác' rồi bấm lại.")
            pendingResult = null
        } else {
            projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val captureIntent = projectionManager?.createScreenCaptureIntent()
            startActivityForResult(captureIntent, SCREEN_RECORD_REQUEST_CODE)
            pendingResult?.success("Hãy chọn 'Bắt đầu truyền phát'...")
            pendingResult = null
        }
    }

    // 3. LẮNG NGHE KẾT QUẢ XIN QUYỀN MICRO TỪ HỆ THỐNG
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == RECORD_AUDIO_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Người dùng ĐỒNG Ý cho phép dùng Micro -> Đi tiếp tục luồng quay màn hình
                startScreenCaptureFlow()
            } else {
                // Người dùng TỪ CHỐI
                pendingResult?.success("Vui lòng cấp quyền Micro để quay có tiếng.")
                pendingResult = null
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
                prefs.edit().putBoolean("isRecordingActive", true).apply()

                val serviceIntent = Intent(this, RecordingService::class.java).apply {
                    putExtra("code", resultCode)
                    putExtra("data", data)
                    putExtra("quality", pendingQuality)
                    putExtra("isAudioEnabled", pendingAudioEnabled) // Gửi tiếp sang Service
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }

                Handler(Looper.getMainLooper()).postDelayed({
                    methodChannel?.invokeMethod("onRecordingStarted", null)
                }, 500)

            } else {
                prefs.edit().putBoolean("isRecordingActive", false)
                    .putBoolean("hasNewVideo", false).apply()

                Handler(Looper.getMainLooper()).postDelayed({
                    methodChannel?.invokeMethod("onRecordingStopped", null)
                }, 500)
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