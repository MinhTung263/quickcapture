package com.quickcapture.vn

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class RecordingService : Service() {
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var mediaRecorder: MediaRecorder? = null
    private val CHANNEL_ID = "ScreenRecordChannel"
    private var isStopping = false
    // Các biến cho Widget Floating
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var tvTime: TextView? = null
    private var secondsElapsed = 0
    private var timerHandler = Handler(Looper.getMainLooper())
    private var timerRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_RECORDING") {
            stopRecording()
            return START_NOT_STICKY
        }

        createNotificationChannel()

        val stopIntent = Intent(this, RecordingService::class.java).apply { action = "STOP_RECORDING" }
        val pendingStopIntent = PendingIntent.getService(this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Quick Capture")
            .setContentText("Đang ghi hình màn hình...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .addAction(android.R.drawable.ic_media_pause, "Dừng quay", pendingStopIntent)
            .setOngoing(true)
            .build()

        startForeground(1, notification)

        val resultCode = intent?.getIntExtra("code", -1) ?: -1
        val data = intent?.getParcelableExtra<Intent>("data")
        val quality = intent?.getStringExtra("quality") ?: "720p"
        val isAudioEnabled = intent?.getBooleanExtra("isAudioEnabled", true) ?: true
        if (resultCode == Activity.RESULT_OK && data != null) {
            startRecording(resultCode, data, quality, isAudioEnabled)
        } else {
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun startRecording(resultCode: Int, data: Intent, quality: String, isAudioEnabled: Boolean) {
        val metrics = DisplayMetrics()
        val winManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        winManager.defaultDisplay.getRealMetrics(metrics)

        var screenWidth = metrics.widthPixels
        var screenHeight = metrics.heightPixels
        val screenDensity = metrics.densityDpi

        var bitRate = 5000000
        var frameRate = 30
        var scaleFactor = 1f

        val maxDimension = Math.max(screenWidth, screenHeight)

        // 1. TÍNH TOÁN LOGIC CHẤT LƯỢNG (Giống hệt iOS)
        when (quality) {
            "1080p" -> {
                scaleFactor = 1f // Giữ nguyên kích thước gốc
                bitRate = (screenWidth * screenHeight * 5.0).toInt() // Bitrate siêu cao
                frameRate = 60
            }
            "480p" -> {
                if (maxDimension > 854) scaleFactor = 854f / maxDimension
                bitRate = 2500000
                frameRate = 30
            }
            else -> { // "720p"
                if (maxDimension > 1280) scaleFactor = 1280f / maxDimension
                bitRate = 5000000
                frameRate = 30
            }
        }

        // Bắt buộc chia hết cho 16 để tránh lỗi H.264
        val finalWidth = (screenWidth * scaleFactor).toInt() / 16 * 16
        val finalHeight = (screenHeight * scaleFactor).toInt() / 16 * 16

        val formatter = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault())
        val fileName = "REC_${formatter.format(Date())}.mp4"

        val directory = getExternalFilesDir(Environment.DIRECTORY_MOVIES)
        if (directory != null && !directory.exists()) directory.mkdirs()
        val filePath = File(directory, fileName).absolutePath

        try {
            mediaRecorder = MediaRecorder().apply {
                // 2. THIẾT LẬP ÂM THANH TRƯỚC
                if (isAudioEnabled) {
                    setAudioSource(MediaRecorder.AudioSource.MIC) // Android bắt buộc dùng MIC
                }

                // 3. THIẾT LẬP VIDEO
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)

                // 4. CẤU HÌNH ENCODER
                if (isAudioEnabled) {
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(128000)
                    setAudioSamplingRate(44100)
                }

                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoSize(finalWidth, finalHeight)
                setVideoEncodingBitRate(bitRate)
                setVideoFrameRate(frameRate)

                setOutputFile(filePath)
                prepare()
            }

            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(resultCode, data)

            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    super.onStop()
                    stopRecording()
                }
            }, null)

            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ScreenRecord",
                finalWidth, finalHeight, screenDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                mediaRecorder?.surface, null, null
            )

            mediaRecorder?.start()

            // Hiển thị Widget nổi sau khi quay thành công
            showFloatingWidget()

        } catch (e: Exception) {
            e.printStackTrace()
            stopSelf()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showFloatingWidget() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // Khai báo layout params cho cửa sổ trôi nổi
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )

        // Vị trí mặc định ở góc trên bên trái
        params.gravity = Gravity.TOP or Gravity.START
        params.x = 50
        params.y = 150

        // 1. Tạo Layout chứa
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(30, 20, 30, 20)
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#E6000000")) // Màu đen hơi trong suốt
                cornerRadius = 50f
            }
        }

        // 2. Chấm đỏ nhấp nháy (Giả lập đèn record)
        val redDot = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(24, 24).apply { setMargins(0, 0, 20, 0) }
            background = GradientDrawable().apply {
                setColor(Color.RED)
                shape = GradientDrawable.OVAL
            }
        }

        // 3. Chữ đếm thời gian
        tvTime = TextView(this).apply {
            text = "00:00"
            setTextColor(Color.WHITE)
            textSize = 15f
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { setMargins(0, 0, 30, 0) }
        }

        // 4. Nút Stop (Hình vuông cam/đỏ)
        val stopBtn = TextView(this).apply {
            text = "⏹" // Biểu tượng Stop
            setTextColor(Color.parseColor("#FF5252"))
            textSize = 22f
            setPadding(10, 0, 0, 0)
            setOnClickListener {
                stopRecording() // Dừng quay ngay lập tức khi bấm
            }
        }

        layout.addView(redDot)
        layout.addView(tvTime)
        layout.addView(stopBtn)

        floatingView = layout
        windowManager?.addView(floatingView, params)

        // Xử lý kéo thả Widget
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f

        layout.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    return@setOnTouchListener false // Trả về false để Button Stop vẫn nhận được click
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - initialTouchX).toInt()
                    params.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(floatingView, params)
                    return@setOnTouchListener true
                }
                else -> return@setOnTouchListener false
            }
        }

        // Khởi động đồng hồ đếm giờ
        startTimer()
    }

    private fun startTimer() {
        secondsElapsed = 0
        timerRunnable = object : Runnable {
            override fun run() {
                secondsElapsed++
                val mins = secondsElapsed / 60
                val secs = secondsElapsed % 60
                tvTime?.text = String.format("%02d:%02d", mins, secs)
                timerHandler.postDelayed(this, 1000) // Lặp lại sau 1 giây
            }
        }
        timerHandler.post(timerRunnable!!)
    }

    private fun removeFloatingWidget() {
        timerRunnable?.let { timerHandler.removeCallbacks(it) }
        floatingView?.let { windowManager?.removeView(it) }
        floatingView = null
    }

    private fun stopRecording() {
        // Chốt chặn: Nếu đang trong quá trình dừng rồi thì không chạy lại nữa
        if (isStopping) return
        isStopping = true

        removeFloatingWidget()

        try {
            mediaRecorder?.stop()
            mediaRecorder?.reset()
        } catch (e: Exception) {
            e.printStackTrace()
        }

        virtualDisplay?.release()
        mediaProjection?.stop() // Lúc này nó có gọi lại onStop() thì cũng bị chốt chặn bật ra

        val prefs = getSharedPreferences("QuickCapturePrefs", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putBoolean("hasNewVideo", true)
            putBoolean("isRecordingActive", false)
            apply()
        }

        // 🚀 Bổ sung setPackage để tín hiệu bay thẳng đích đến MainActivity mà không bị Android chặn
        val broadcastIntent = Intent("com.quickcapture.vn.VIDEO_SAVED")
        broadcastIntent.setPackage(packageName)
        sendBroadcast(broadcastIntent)

        stopForeground(true)
        stopSelf()
    }

    private fun createNotificationChannel() {
        // ... (Giữ nguyên cấu hình NotificationChannel như cũ)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Trạng thái quay màn hình",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}