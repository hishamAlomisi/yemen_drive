import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:record/record.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import 'ride_controller.dart';

/// Records PCM audio only after an explicit in-ride consent and forwards it
/// directly to the authenticated safety endpoint in bounded chunks.
class SafetyRecordingController extends GetxController {
  SafetyRecordingController(this._api, this._ride);

  final ApiClient _api;
  final RideController _ride;
  final AudioRecorder _recorder = AudioRecorder();
  final RxBool isRecording = false.obs;
  final RxBool isWorking = false.obs;
  final RxString error = ''.obs;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final Stopwatch _stopwatch = Stopwatch();
  StreamSubscription<Uint8List>? _audioSubscription;
  Future<void> _uploadQueue = Future<void>.value();
  int? _recordingId;
  int _nextSequence = 0;

  static const int _chunkBytes = 64 * 1024;

  Future<bool> start() async {
    if (isWorking.value || isRecording.value) return false;
    final rideId = int.tryParse(_ride.currentRideId ?? '');
    if (rideId == null) {
      error.value = 'لا توجد رحلة نشطة لتسجيل السلامة.';
      return false;
    }

    isWorking.value = true;
    error.value = '';
    try {
      final created = await _api.execute<Object?>(
        model: 'SafetyRecordingModel',
        operation: 'add',
        data: <String, Object?>{'rideId': rideId, 'consent': true},
      );
      if (created is! ApiSuccess<Object?> || created.data is! Map) {
        error.value = _failureMessage(created);
        return false;
      }
      final id = int.tryParse('${(created.data as Map)['id'] ?? ''}');
      if (id == null) {
        error.value = 'تعذر إنشاء جلسة تسجيل السلامة.';
        return false;
      }
      if (!await _recorder.hasPermission()) {
        error.value = 'لم تُمنح صلاحية الميكروفون لتسجيل السلامة.';
        return false;
      }

      _recordingId = id;
      _nextSequence = 0;
      _buffer.clear();
      _uploadQueue = Future<void>.value();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _stopwatch
        ..reset()
        ..start();
      isRecording.value = true;
      _audioSubscription = stream.listen(
        _onAudio,
        onError: (_) => _stopAfterStreamFailure(),
        cancelOnError: true,
      );
      return true;
    } on Object {
      error.value = 'تعذر بدء تسجيل السلامة. تحقق من الاتصال ثم حاول مجدداً.';
      return false;
    } finally {
      isWorking.value = false;
    }
  }

  Future<void> stop() async {
    if (!isRecording.value || isWorking.value) return;
    isWorking.value = true;
    try {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _flushBuffer();
      await _uploadQueue;
      await _recorder.stop();
      await _finalizeRemote();
    } on Object {
      error.value = 'توقف التسجيل، لكن تعذر تأكيد حفظه على الخادم.';
    } finally {
      _stopwatch.stop();
      _recordingId = null;
      isRecording.value = false;
      isWorking.value = false;
    }
  }

  void _onAudio(Uint8List bytes) {
    if (!isRecording.value) return;
    _buffer.add(bytes);
    if (_buffer.length >= _chunkBytes) unawaited(_flushBuffer());
  }

  Future<void> _flushBuffer() async {
    if (_buffer.isEmpty || _recordingId == null) return;
    final chunk = _buffer.takeBytes();
    final id = _recordingId!;
    final sequence = _nextSequence++;
    _uploadQueue = _uploadQueue.then((_) async {
      await _api.dio.post<Object?>(
        'safety/recordings/$id/chunks/$sequence',
        data: Uint8List.fromList(chunk),
        options: Options(contentType: 'application/octet-stream'),
      );
    });
    try {
      await _uploadQueue;
    } on Object {
      error.value = 'تعذر رفع مقطع السلامة. تم إيقاف التسجيل لحماية سلامة السجل.';
      await _stopAfterStreamFailure();
    }
  }

  Future<void> _stopAfterStreamFailure() async {
    if (!isRecording.value) return;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    _stopwatch.stop();
    try {
      await _finalizeRemote();
    } on Object {
      // The upload failure is already reported to the user; a later start seals
      // this partial session before it creates a new one.
    }
    _recordingId = null;
    isRecording.value = false;
  }

  Future<void> _finalizeRemote() async {
    final id = _recordingId;
    if (id == null) return;
    await _api.dio.post<Object?>(
      'safety/recordings/$id/complete',
      data: <String, Object?>{
        'durationMilliseconds': _stopwatch.elapsedMilliseconds,
      },
    );
  }

  String _failureMessage(ApiResult<Object?> result) => result is ApiFailure<Object?>
      ? result.problem.title
      : 'تعذر بدء تسجيل السلامة.';

  @override
  void onClose() {
    unawaited(_audioSubscription?.cancel());
    unawaited(_recorder.dispose());
    super.onClose();
  }
}
