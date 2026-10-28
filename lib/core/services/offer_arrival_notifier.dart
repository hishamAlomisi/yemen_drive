import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';

/// A displayed offer is announced once, including after a reconnect or restart.
class OfferArrivalNotifier {
  OfferArrivalNotifier({Future<void> Function()? play, GetStorage? storage})
      : _play = play ?? _playNative,
        _storage = storage ?? GetStorage();

  static const _channel = MethodChannel('yemen_drive/offer_sound');
  static const _storageKey = 'announced_driver_offers_v1';
  final Future<void> Function() _play;
  final GetStorage _storage;
  Set<String>? _seen;
  Future<void> _queue = Future<void>.value();

  Future<void> announce(String rideId, String offerId) async {
    _seen ??= (_storage.read<List<dynamic>>(_storageKey) ?? const [])
        .whereType<String>()
        .toSet();
    if (!_seen!.add('$rideId:$offerId')) return;
    // Retain recent identities across process restarts without growing forever.
    while (_seen!.length > 500) {
      _seen!.remove(_seen!.first);
    }
    final task = _queue.then((_) async {
      try {
        await _storage.write(_storageKey, _seen!.toList(growable: false));
      } on Object {
        // Session de-duplication still works when local storage is unavailable.
      }
      try {
        await _play();
      } on Object {
        // Audio failure must never hide an offer or break negotiation.
      }
    });
    _queue = task;
    await task;
  }

  static Future<void> _playNative() async {
    try {
      await _channel.invokeMethod<void>('playOffer');
    } on MissingPluginException {
      await SystemSound.play(SystemSoundType.alert);
    }
  }
}
