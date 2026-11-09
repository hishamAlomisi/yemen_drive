import 'package:flutter/services.dart';

Future<void> playChatMessageSound() async {
  try {
    await const MethodChannel('yemen_drive/chat_sound')
        .invokeMethod<void>('play');
  } on MissingPluginException {
    await SystemSound.play(SystemSoundType.alert);
  } on PlatformException {
    // Audio must not interrupt delivery or acknowledgments.
  }
}
