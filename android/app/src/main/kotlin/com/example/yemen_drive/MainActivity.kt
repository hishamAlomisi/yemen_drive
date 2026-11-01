package com.example.yemen_drive

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager

class MainActivity : FlutterActivity() {
    private val offerPlayers = mutableSetOf<MediaPlayer>()
    private var arrivalPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        arrivalPlayer?.release(); arrivalPlayer = null
        offerPlayers.forEach { it.release() }
        offerPlayers.clear()
        super.onDestroy()
    }
}
