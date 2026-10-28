package com.example.yemen_drive

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioAttributes
import android.media.MediaPlayer

class MainActivity : FlutterActivity() {
    private val offerPlayers = mutableSetOf<MediaPlayer>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        offerPlayers.forEach { it.release() }
        offerPlayers.clear()
        super.onDestroy()
    }
}
