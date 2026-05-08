package com.quickcapture

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import android.content.ContentValues
import android.provider.MediaStore
import java.io.FileInputStream
import java.io.FileOutputStream

class RecordingService : Service() {

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var isRecording = false
    companion object {
        var videoPath: String = ""
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_RECORDING") {
            stopRecording()
            stopSelf()
            return START_NOT_STICKY
        }

        // 1. Khởi tạo Notification Channel & Foreground Service
        val channelId = "screen_record_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "Screen Recording", NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Screen Recorder")
            .setContentText("Đang quay màn hình...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, notification)
        }

        // 2. Nhận Intent an toàn cho Android 13/14
        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra("data", Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra("data")
        }

        if (resultCode == Activity.RESULT_OK && data != null) {
            startRecording(resultCode, data)
        }

        return START_NOT_STICKY
    }

    private fun startRecording(resultCode: Int, data: Intent) {
        try {
            mediaProjectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

            // Lấy kích thước thật của màn hình
            val metrics = resources.displayMetrics
            var width = metrics.widthPixels
            var height = metrics.heightPixels

            // Bắt buộc phải là bội số của 16
            width -= width % 16
            height -= height % 16

            setupMediaRecorder(width, height)

            mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data)

            // ==========================================
            // THÊM ĐOẠN CALLBACK NÀY CHO ANDROID 14+
            // ==========================================
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    super.onStop()
                    Log.d("RecordingService", "Hệ thống hoặc người dùng đã ngắt MediaProjection")
                    // Dọn dẹp tài nguyên nếu bị ngắt đột ngột
                    stopRecording()
                    stopSelf()
                }
            }, null)
            // ==========================================

            val surface = mediaRecorder?.surface
            if (surface != null) {
                mediaProjection?.createVirtualDisplay(
                    "ScreenRec",
                    width, height, metrics.densityDpi,
                    android.hardware.display.DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    surface, null, null
                )
                mediaRecorder?.start()

                // Đánh dấu là ĐANG QUAY
                isRecording = true

                Log.d("RecordingService", "Bắt đầu quay thành công!")
            }
        } catch (e: Exception) {
            Log.e("RecordingService", "Lỗi khởi tạo quay màn hình: ${e.message}")
            e.printStackTrace()
            stopSelf()
        }
    }

    private fun setupMediaRecorder(width: Int, height: Int) {
        val dir = getExternalFilesDir(Environment.DIRECTORY_MOVIES)
        val file = File(dir, "record_${System.currentTimeMillis()}.mp4")
        videoPath = file.absolutePath

        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        mediaRecorder?.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setVideoSource(MediaRecorder.VideoSource.SURFACE)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setOutputFile(videoPath)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)

            setVideoEncoder(MediaRecorder.VideoEncoder.H264)

            // 3. Hạ Bitrate xuống 5 Mbps (mức an toàn cho mọi dòng máy)
            setVideoEncodingBitRate(5000000)
            setVideoFrameRate(30)
            setVideoSize(width, height)

            try {
                prepare()
            } catch (e: Exception) {
                Log.e("RecordingService", "Lỗi Prepare MediaRecorder: ${e.message}")
            }
        }
    }

    private fun stopRecording() {
        // Nếu đã dừng rồi thì không làm gì nữa, tránh bị Double Stop
        if (!isRecording) return
        isRecording = false

        try {
            mediaRecorder?.stop()
        } catch (e: Exception) {
            Log.e("RecordingService", "Lỗi khi stop MediaRecorder (thường do quay quá ngắn): ${e.message}")
        } finally {
            // Đảm bảo luôn giải phóng tài nguyên dù bị lỗi
            try {
                mediaRecorder?.reset()
                mediaRecorder?.release()
                mediaRecorder = null

                // Gọi hàm lưu vào thư viện (nếu bạn đang dùng hàm saveVideoToGallery đã làm ở bước trước)
                if (videoPath.isNotEmpty()) {
                    saveVideoToGallery(videoPath)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        try {
            mediaProjection?.stop()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            mediaProjection = null
        }
    }
    private fun saveVideoToGallery(filePath: String) {
        val file = File(filePath)
        if (!file.exists()) return

        try {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                // Lưu vào thư mục Movies/ScreenRecords của điện thoại
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/ScreenRecords")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
            }

            val resolver = contentResolver
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }

            val itemUri = resolver.insert(collection, values)

            if (itemUri != null) {
                resolver.openOutputStream(itemUri).use { out ->
                    FileInputStream(file).use { input ->
                        input.copyTo(out!!)
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.Video.Media.IS_PENDING, 0)
                    resolver.update(itemUri, values, null, null)
                }

                // Xoá file gốc trong thư mục ẩn của app để giải phóng bộ nhớ
                file.delete()

                // Cập nhật lại đường dẫn để báo về Flutter
                videoPath = "Đã lưu vào Ảnh/Video (Movies/ScreenRecords/${file.name})"
            }
        } catch (e: Exception) {
            e.printStackTrace()
            Log.e("RecordingService", "Lỗi khi lưu vào Gallery: ${e.message}")
        }
    }
}