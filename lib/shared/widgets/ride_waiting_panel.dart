import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_models.dart';
import '../../core/realtime/realtime_state_binding.dart';
import '../models/ride_waiting_snapshot.dart';

/// The rider follows the driver's stop and may ask the driver to resume.
/// Local time only animates the server's last snapshot.
class RideWaitingPanel extends StatefulWidget {
  const RideWaitingPanel({
    required this.rideId,
    this.onChanged,
    super.key,
  });
  final int rideId;
  final VoidCallback? onChanged;

  @override
  State<RideWaitingPanel> createState() => _RideWaitingPanelState();
}

class _RideWaitingPanelState extends State<RideWaitingPanel>
    with WidgetsBindingObserver {
  Map<String, Object?>? _data;
  Timer? _timer;
  RealtimeStateBinding? _stateBinding;
  final _elapsed = Stopwatch();
  bool _loading = false;
  bool _busy = false;
  bool _paused = false;
  String? _error;
  String? _requestKey;
  int _ticks = 0;
  int _revision = 0;
  int _refreshId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateBinding = RealtimeStateBinding(
        owner: this,
        resources: const {'ride'},
        accepts: (change) =>
            change.resource == 'ride' && change.resourceId == widget.rideId,
        refresh: () => _refresh(requireSuccess: true));
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused || !TickerMode.of(context)) return;
      if (++_ticks % 5 == 0 && _stateBinding?.synchronized != true) {
        unawaited(_refresh());
      }
      if (_session['isOpen'] == true) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant RideWaitingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rideId == widget.rideId) return;
    ++_revision;
    ++_refreshId;
    _loading = false;
    _busy = false;
    _data = null;
    _error = null;
    _requestKey = null;
    _elapsed.reset();
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (!_paused) unawaited(_refresh());
  }

  Map<String, Object?> get _session => _map(_data?['session']);
  static Map<String, Object?> _map(Object? raw) =>
      raw is Map ? Map<String, Object?>.from(raw) : {};
  static double _number(Object? raw) => RideWaitingSnapshot.number(raw);

  Future<Map<String, Object?>> _call(String operation) async {
    final result = await Get.find<ApiClient>().execute<Object?>(
      model: 'RideWaitingModel',
      operation: operation,
      data: {
        'rideId': widget.rideId,
        if (operation != 'get') 'sessionId': _session['id'],
        if (operation == 'request_resume') 'requestKey': _requestKey,
      },
    );
    if (result is ApiFailure) {
      throw FormatException(result.problem.detail ?? result.problem.title);
    }
    final data = _map((result as ApiSuccess).data);
    RideWaitingSnapshot(data);
    return data;
  }

  void _apply(Map<String, Object?> value) {
    final oldSessionId = _session['id'];
    final old =
        '${_session['id']}-${_session['isOpen']}-${_session['startedAtUtc']}-${_data?['settledWaitingFee']}';
    setState(() {
      _data = value;
      _error = null;
      _elapsed
        ..reset()
        ..start();
    });
    final next =
        '${_session['id']}-${_session['isOpen']}-${_session['startedAtUtc']}-${_data?['settledWaitingFee']}';
    if (_session['id'] != oldSessionId) _requestKey = null;
    if (_map(_session['resumeRequest'])['requestKey'] == _requestKey) {
      _requestKey = null;
    }
    if (old != next) widget.onChanged?.call();
  }

  Future<void> _refresh({bool requireSuccess = false}) async {
    if (_loading || _busy) {
      if (requireSuccess) throw StateError('Waiting refresh is in progress');
      return;
    }
    _loading = true;
    final revision = _revision;
    final refreshId = ++_refreshId;
    final epoch = _stateBinding?.epoch;
    try {
      final value = await _call('get');
      if (epoch != null) _stateBinding?.verify(epoch);
      if (mounted && revision == _revision) _apply(value);
    } catch (error) {
      if (mounted &&
          revision == _revision &&
          error is! StateSnapshotSuperseded) {
        setState(() => _error = 'تعذرت مزامنة الانتظار. أعد المحاولة.');
      }
      if (requireSuccess) rethrow;
    } finally {
      if (refreshId == _refreshId) _loading = false;
    }
  }

  String _policyText() =>
      'المهلة المجانية لكل توقف: ${_data?['waitingFreeMinutes'] ?? 0} دقيقة.\n'
      'بعدها ${_data?['waitingPricePerMinute'] ?? 0} ر.ي للدقيقة، باحتساب الثواني.\n'
      'سقف الانتظار لجميع توقفات الرحلة: ${_data?['waitingMaxFee'] ?? 0} ر.ي.\n'
      'يبدأ الوقت فور بدء السائق التوقف. ينتهي باستئناف السائق، أو الحركة المؤكدة، أو بلوغ السقف. ويتوقف إذا انقطع تحديث موقع السائق لدقيقتين.';

  Future<void> _requestResume() async {
    if (_busy ||
        _data == null ||
        !RideWaitingSnapshot(_data!).canRequestResume ||
        _error != null ||
        (_elapsed.elapsed.inSeconds >= 15 &&
            _stateBinding?.synchronized != true)) return;
    if (_requestKey == null) {
      final random = math.Random.secure();
      final hex = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _requestKey ??=
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    }
    final revision = ++_revision;
    setState(() => _busy = true);
    try {
      final data = await _call('request_resume');
      if (!mounted || revision != _revision) return;
      _apply(data);
      _requestKey = null;
    } catch (error) {
      if (mounted && revision == _revision) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'تعذر تنفيذ الطلب. حدّث الحالة وحاول مجددًا.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _busy = false);
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return _error == null
          ? const SizedBox.shrink()
          : TextButton(onPressed: _refresh, child: Text(_error!));
    }
    final snapshot = RideWaitingSnapshot(_data!);
    final session = _session;
    final open = snapshot.isOpen;
    final active = snapshot.isActive;
    if (!open &&
        _number(_data?['waitingFee']) == 0 &&
        session['endReason'] == null) {
      return const SizedBox.shrink();
    }
    final seconds = snapshot.elapsedSeconds(_elapsed.elapsed);
    final freeSeconds = (_number(session['freeMinutes']) * 60).toInt();
    final waitingFee = snapshot.waitingFee(_elapsed.elapsed);
    final total = snapshot.totalAmount(_elapsed.elapsed);
    final pending = open && !active;
    final stale = _error != null ||
        (_elapsed.elapsed.inSeconds >= 15 &&
            _stateBinding?.synchronized != true);
    final busy = _busy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              active
                  ? 'الرحلة متوقفة'
                  : pending
                      ? 'بانتظار تحديث حالة التوقف'
                      : 'الانتظار أثناء الرحلة',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (active) ...[
              const Text('بدأ السائق التوقف. السائق هو من يستأنف الرحلة.'),
              Text(
                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                seconds < freeSeconds
                    ? 'المتبقي مجانًا: ${(freeSeconds - seconds + 59) ~/ 60} دقيقة'
                    : 'بدأ احتساب رسوم الانتظار',
              ),
              Text(_policyText()),
            ],
            if (pending)
              const Text(
                  'تُحدّث حالة التوقف من الخادم. لم يبدأ عداد الانتظار.'),
            if (snapshot.resumeRequestPending)
              const Text(
                'أُرسل طلب الاستئناف. بانتظار موافقة السائق؛ يستمر عداد الانتظار حتى الاستئناف.',
              ),
            if (active &&
                !snapshot.resumeRequestPending &&
                _map(session['resumeRequest'])['decision'] == 'rejected')
              const Text(
                  'لم يوافق السائق على طلب الاستئناف. ما زال التوقف مستمرًا.'),
            Text(
              'أجرة الرحلة ${_number(_data?['baseFare']).toStringAsFixed(0)} + الخدمة ${_number(_data?['serviceFee']).toStringAsFixed(0)} + الانتظار ${waitingFee.toStringAsFixed(0)} ر.ي',
            ),
            Text('الإجمالي الحالي: ${total.toStringAsFixed(0)} ر.ي'),
            if (!open && session['endReason'] != null)
              Text(
                switch (session['endReason']) {
                  'connection_lost' => 'أُوقف الانتظار لانقطاع تحديث الموقع.',
                  'vehicle_moving' => 'أُوقف الانتظار بعد تأكد حركة السيارة.',
                  'fee_cap' => 'وصل الانتظار إلى سقف الرسوم.',
                  'driver_resumed' => 'استأنف السائق الرحلة وانتهى الانتظار.',
                  _ => 'انتهى التوقف.'
                },
              ),
            if (stale)
              TextButton(
                onPressed: _refresh,
                child: const Text('بانتظار المزامنة — تحديث الحالة'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (snapshot.canRequestResume)
              OutlinedButton.icon(
                onPressed: busy || stale ? null : _requestResume,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('طلب استئناف الرحلة'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stateBinding?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }
}
