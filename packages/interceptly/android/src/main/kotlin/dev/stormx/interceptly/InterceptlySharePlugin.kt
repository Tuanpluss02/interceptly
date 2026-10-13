package dev.stormx.interceptly

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class InterceptlySharePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: android.app.Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "dev.stormx.interceptly/share")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "shareFile") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "Missing file path", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "File does not exist: $path", null)
            return
        }
        val hostActivity = activity
        if (hostActivity == null) {
            result.error("NO_ACTIVITY", "No attached activity", null)
            return
        }
        try {
            val authority = "${hostActivity.packageName}.interceptly.fileprovider"
            val uri = FileProvider.getUriForFile(hostActivity, authority, file)
            val mimeType = call.argument<String>("mimeType") ?: "*/*"
            val subject = call.argument<String>("subject")
            val text = call.argument<String>("text")
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                text?.let { putExtra(Intent.EXTRA_TEXT, it) }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            hostActivity.startActivity(Intent.createChooser(sendIntent, subject))
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message, null)
        }
    }
}
