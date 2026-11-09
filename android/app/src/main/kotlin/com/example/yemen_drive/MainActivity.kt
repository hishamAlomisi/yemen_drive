package com.example.yemen_drive

import com.yemendrive.otp.OtpSmsBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private var otpSms: OtpSmsBridge? = null
    private val offerPlayers = mutableSetOf<MediaPlayer>()
    private var arrivalPlayer: MediaPlayer? = null
    private var chatTone: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        otpSms?.dispose()
        otpSms = OtpSmsBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yemen_drive/chat_sound")
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    chatTone?.release()
                    val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 35)
                    chatTone = tone
                    tone.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (chatTone === tone) { tone.release(); chatTone = null }
                    }, 220)
                    result.success(null)
                } catch (_: Exception) {
                    chatTone?.release(); chatTone = null
                    result.success(null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yemen_drive/arrival_sound")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            if (arrivalPlayer == null) {
                                val player = MediaPlayer()
                                player.setAudioAttributes(AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                                player.setDataSource(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                                player.isLooping = true
                                player.prepare()
                                arrivalPlayer = player
                                player.start()
                            }
                            result.success(null)
                        }
                        "stop" -> { arrivalPlayer?.release(); arrivalPlayer = null; result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    arrivalPlayer?.release(); arrivalPlayer = null
                    result.error("arrival_sound_failed", "Could not play arrival sound", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yemen_drive/offer_sound")
            .setMethodCallHandler { call, result ->
                if (call.method != "playOffer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val player = MediaPlayer()
                    player.setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    resources.openRawResourceFd(R.raw.driver_offer).use { descriptor ->
                        player.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
                    }
                    player.setOnCompletionListener {
                        offerPlayers.remove(it)
                        it.release()
                        result.success(null)
                    }
                    player.setOnErrorListener { failed, _, _ ->
                        offerPlayers.remove(failed)
                        failed.release()
                        result.success(null)
                        true
                    }
                    player.prepare()
                    offerPlayers.add(player)
                    player.start()
                } catch (_: Exception) {
                    result.success(null)
                }
            }
    }

    override fun onDestroy() {
        otpSms?.dispose(); otpSms = null
        chatTone?.release(); chatTone = null
        arrivalPlayer?.release(); arrivalPlayer = null
        offerPlayers.forEach { it.release() }
        offerPlayers.clear()
        super.onDestroy()
    }
}
