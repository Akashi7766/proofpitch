package dev.proofpitch.proof_pitch

import android.content.Intent
import android.os.Bundle
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Receives "Share → ProofPitch" from LinkedIn, Reddit, WhatsApp, Chrome… and hands the text to Dart.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pending = sharedText(intent) // before super: Dart may ask as soon as the engine starts
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "proofpitch/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialShare" -> {
                        result.success(pending)
                        pending = null
                    }
                    // Save / share a generated PDF (tailored resume) via the system sheet: Drive, Files, WhatsApp…
                    "sharePdf" -> {
                        val file = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this@MainActivity, "$packageName.file_provider", file)
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "application/pdf"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(send, "Save or share your resume"))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // App already open (singleTop): push the new share straight to Dart.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("shared", it) }
    }

    private fun sharedText(i: Intent?): String? {
        if (i?.action != Intent.ACTION_SEND || i.type?.startsWith("text/") != true) return null
        return listOfNotNull(i.getStringExtra(Intent.EXTRA_SUBJECT), i.getStringExtra(Intent.EXTRA_TEXT))
            .joinToString("\n").ifBlank { null }
    }
}
