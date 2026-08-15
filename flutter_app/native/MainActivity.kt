package com.sahjanand.sahjanand

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sahjanand.recorder"
    private val MIC_PERMISSION_CODE = 200
    private var mediaRecorder: MediaRecorder? = null
    private var recordingPath: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_PATH", "Path is required", null)
                        return@setMethodCallHandler
                    }
                    
                    // Check mic permission at native level
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        // Request permission
                        pendingResult = result
                        pendingPath = path
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), MIC_PERMISSION_CODE)
                        return@setMethodCallHandler
                    }
                    
                    try {
                        startRecording(path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RECORDING_ERROR", e.message ?: "Failed to start recording", null)
                    }
                }
                "stopRecording" -> {
                    try {
                        val path = stopRecording()
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message ?: "Failed to stop recording", null)
                    }
                }
                "cancelRecording" -> {
                    try {
                        cancelRecording()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_ERROR", e.message ?: "Failed to cancel", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MIC_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Permission granted, start recording
                val path = pendingPath
                val result = pendingResult
                pendingPath = null
                pendingResult = null
                if (path != null && result != null) {
                    try {
                        startRecording(path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RECORDING_ERROR", e.message ?: "Failed to start recording", null)
                    }
                }
            } else {
                // Permission denied
                pendingResult?.error("PERMISSION_DENIED", "Microphone permission denied", null)
                pendingResult = null
                pendingPath = null
            }
        }
    }

    private fun startRecording(path: String) {
        stopRecorderSafely()
        recordingPath = path

        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        mediaRecorder?.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioEncodingBitRate(128000)
            setAudioSamplingRate(44100)
            setOutputFile(path)
            prepare()
            start()
        }
    }

    private fun stopRecording(): String? {
        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            // Ignore stop errors (e.g., if recording was too short)
        }
        mediaRecorder = null
        val path = recordingPath
        recordingPath = null
        return path
    }

    private fun cancelRecording() {
        stopRecorderSafely()
        recordingPath?.let {
            val file = File(it)
            if (file.exists()) file.delete()
        }
        recordingPath = null
    }

    private fun stopRecorderSafely() {
        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            try {
                mediaRecorder?.release()
            } catch (e2: Exception) {
                // Ignore
            }
        }
        mediaRecorder = null
    }
}
