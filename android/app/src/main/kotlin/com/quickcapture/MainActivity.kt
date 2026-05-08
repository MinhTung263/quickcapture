package com.quickcapture

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    private val CHANNEL = "quick_capture"
    private var mediaProjectionManager: MediaProjectionManager? = null

    private val REQUEST_CODE_SCREEN_CAPTURE = 1001
    private val REQUEST_CODE_PERMISSIONS = 1002

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaProjectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when(call.method) {
                "startRecord" -> {
                    pendingResult = result
                    checkAndRequestPermissions()
                }
                "stopRecord" -> {
                    stopRecording()
                    // Lấy videoPath từ Service trả về cho Flutter
                    result.success(RecordingService.videoPath)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkAndRequestPermissions() {
        val permissionsNeeded = mutableListOf(Manifest.permission.RECORD_AUDIO)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissionsNeeded.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        val listPermissionsNeeded = permissionsNeeded.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (listPermissionsNeeded.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this, listPermissionsNeeded.toTypedArray(), REQUEST_CODE_PERMISSIONS
            )
        } else {
            startScreenCaptureIntent()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == REQUEST_CODE_PERMISSIONS) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (allGranted) {
                startScreenCaptureIntent()
            } else {
                pendingResult?.error("PERMISSION_DENIED", "Bạn cần cấp quyền để quay video", null)
                pendingResult = null
            }
        }
    }

    private fun startScreenCaptureIntent() {
        val captureIntent = mediaProjectionManager!!.createScreenCaptureIntent()
        startActivityForResult(captureIntent, REQUEST_CODE_SCREEN_CAPTURE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode != Activity.RESULT_OK || data == null) {
                pendingResult?.error("DENIED", "User denied screen recording", null)
                pendingResult = null
                return
            }

            // Truyền ResultCode và Data sang cho RecordingService xử lý
            val serviceIntent = Intent(this, RecordingService::class.java).apply {
                putExtra("resultCode", resultCode)
                putExtra("data", data) // Truyền Intent data qua Service
            }
            ContextCompat.startForegroundService(this, serviceIntent)

            // Báo về cho Flutter là đã bắt đầu quay
            pendingResult?.success(null)
            pendingResult = null
        }
    }

    private fun stopRecording() {
        // Gửi lệnh tắt sang RecordingService
        val serviceIntent = Intent(this, RecordingService::class.java).apply {
            action = "STOP_RECORDING"
        }
        startService(serviceIntent)
    }
}