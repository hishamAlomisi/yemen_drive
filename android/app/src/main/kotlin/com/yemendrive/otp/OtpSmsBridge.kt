package com.yemendrive.otp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/** Receives only Play-services broadcasts for an SMS bearing this app's hash. */
class OtpSmsBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "yemen_drive/otp_sms")
    private var receiver: BroadcastReceiver? = null
    private var pendingCode: String? = null
    private var generation = 0

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "takePendingCode" -> {
                    result.success(pendingCode)
                    pendingCode = null
                }
                "stop" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun appHash(): String {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        } else {
            context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
        }
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else { info.signatures }
        val signature = signatures?.firstOrNull() ?: error("Missing signing certificate")
        val input = "${context.packageName} ${signature.toCharsString()}"
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(digest.copyOfRange(0, 9), Base64.NO_PADDING or Base64.NO_WRAP).take(11)
    }

    private fun start(result: MethodChannel.Result) {
        stop()
        val attempt = generation
        try {
            val hash = appHash()
            val listener = object : BroadcastReceiver() {
                @Suppress("DEPRECATION")
                override fun onReceive(context: Context, intent: Intent) {
                    if (attempt != generation || intent.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                    val status = intent.extras?.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return
                    if (status.statusCode == CommonStatusCodes.SUCCESS) {
                        val message = intent.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE) ?: return
                        if (!message.contains("يمن درايف") || !message.trimEnd().endsWith(hash)) return
                        val normalized = message.substringBeforeLast(hash).map { char ->
                            val digit = Character.digit(char, 10)
                            if (digit >= 0) ('0'.code + digit).toChar() else char
                        }.joinToString("")
                        val code = Regex("(?<![0-9])[0-9]{6}(?![0-9])").find(normalized)?.value ?: return
                        pendingCode = code
                        channel.invokeMethod("code", code)
                        unregister()
                    } else if (status.statusCode == CommonStatusCodes.TIMEOUT) {
                        unregister()
                    }
                }
            }
            receiver = listener
            val filter = IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION)
            // SEND_PERMISSION authenticates the source; no inbox/SMS permission is requested.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(listener, filter, SmsRetriever.SEND_PERMISSION, null, Context.RECEIVER_EXPORTED)
            } else {
                context.registerReceiver(listener, filter, SmsRetriever.SEND_PERMISSION, null)
            }
            SmsRetriever.getClient(context).startSmsRetriever()
                .addOnSuccessListener { result.success(if (attempt == generation) hash else null) }
                .addOnFailureListener {
                    if (attempt == generation) stop()
                    result.success(null)
                }
        } catch (_: Exception) {
            if (attempt == generation) stop()
            result.success(null)
        }
    }

    private fun unregister() {
        receiver?.let { try { context.unregisterReceiver(it) } catch (_: IllegalArgumentException) {} }
        receiver = null
    }

    private fun stop() {
        generation++
        unregister()
        pendingCode = null
    }

    fun dispose() {
        stop()
        channel.setMethodCallHandler(null)
    }
}
