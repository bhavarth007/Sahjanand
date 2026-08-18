package com.sahjanand.sahjanand

import android.media.MediaRecorder
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sahjanand.recorder"
    private var mediaRecorder: MediaRecorder? = null
    private var recordingPath: String? = null

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
                        result.error("STOP_ERROR", e.message ?: "Failed to stop", null)
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

    private fun startRecording(path: String) {
        stopRecorderSafely()
        recordingPath = path
        val file = File(path)
        file.parentFile?.mkdirs()

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
            mediaRecorder?.apply { stop(); release() }
        } catch (e: Exception) { /* ignore */ }
        mediaRecorder = null
        val path = recordingPath
        recordingPath = null
        return path
    }

    private fun cancelRecording() {
        stopRecorderSafely()
        recordingPath?.let { File(it).takeIf { f -> f.exists() }?.delete() }
        recordingPath = null
    }

    private fun stopRecorderSafely() {
        try { mediaRecorder?.apply { stop(); release() } }
        catch (e: Exception) { try { mediaRecorder?.release() } catch (_: Exception) {} }
        mediaRecorder = null
    }
}
