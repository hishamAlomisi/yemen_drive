import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_models.dart';
import '../models/ride_waiting_snapshot.dart';

/// Server-approved waiting. Local time only animates the server's last snapshot.
class RideWaitingPanel extends StatefulWidget {
  const RideWaitingPanel({
    required this.rideId,
    this.isDriver = false,
    this.onChanged,
    super.key,
  });
  final int rideId;
  final bool isDriver;
  final VoidCallback? onChanged;

  @override
  State<RideWaitingPanel> createState() => _RideWaitingPanelState();
}

class _RideWaitingPanelState extends State<RideWaitingPanel>
    with WidgetsBindingObserver {
  Map<String, Object?>? _data;
  Timer? _timer;
  final _elapsed = Stopwatch();
  bool _loading = false;
  bool _busy = false;
  bool _confirming = false;
  String? _error;
  String? _requestKey;
  int _ticks = 0;
  int _revision = 0;
  int _refreshId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (++_ticks % 5 == 0) unawaited(_refresh());
      if (_data != null) setState(() {});
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
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
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
        if (operation == 'add') 'requestKey': _requestKey,
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
    if (old != next) widget.onChanged?.call();
  }

  Future<void> _refresh() async {
    if (_loading || _busy) return;
    _loading = true;
    final revision = _revision;
    final refreshId = ++_refreshId;
    try {
      final value = await _call('get');
      if (mounted && revision == _revision) _apply(value);
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = 'تعذرت مزامنة الانتظار. أعد المحاولة.');
      }
    } finally {
      if (refreshId == _refreshId) _loading = false;
    }
  }

  String _policyText() =>
      'المهلة المجانية لكل توقف: ${_data?['waitingFreeMinutes'] ?? 0} دقيقة.\n'
      'بعدها ${_data?['waitingPricePerMinute'] ?? 0} ر.ي للدقيقة، باحتساب الثواني.\n'
      'سقف الانتظار لجميع توقفات الرحلة: ${_data?['waitingMaxFee'] ?? 0} ر.ي.\n'
      'يبدأ الوقت عند موافقة الطرف الآخر. ينتهي باستئناف السائق، أو الحركة المؤكدة، أو بلوغ السقف. ويتوقف إذا انقطع تحديث موقع السائق لدقيقتين.';

  Future<void> _action(String operation) async {
    if (_busy || _confirming) return;
    final rideId = widget.rideId;
    final sessionId = _session['id'];
    if (operation == 'add' || operation == 'accept') {
      setState(() => _confirming = true);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            operation == 'add' ? 'توقف بطلب الراكب' : 'الموافقة على الانتظار',
          ),
          content: SingleChildScrollView(child: Text(_policyText())),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                operation == 'add' ? 'إرسال الطلب' : 'أوافق على بدء الانتظار',
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _confirming = false);
      if (accepted != true || rideId != widget.rideId) return;
      if (sessionId != _session['id'] ||
          _data?[operation == 'add' ? 'canRequest' : 'canDecide'] != true ||
          _error != null ||
          _elapsed.elapsed.inSeconds >= 15) {
        unawaited(_refresh());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تغيرت حالة الانتظار. راجع الحالة المحدثة.'),
          ),
        );
        return;
      }
    }
    if (operation == 'add') {
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
      final data = await _call(operation);
      if (!mounted || revision != _revision) return;
      _apply(data);
      if (operation == 'add') _requestKey = null;
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
        _data?['canRequest'] != true &&
        _number(_data?['waitingFee']) == 0) {
      return const SizedBox.shrink();
    }
    final seconds = snapshot.elapsedSeconds(_elapsed.elapsed);
    final freeSeconds = (_number(session['freeMinutes']) * 60).toInt();
    final waitingFee = snapshot.waitingFee(_elapsed.elapsed);
    final total = snapshot.totalAmount(_elapsed.elapsed);
    final pending = open && !active;
    final stale = _error != null || _elapsed.elapsed.inSeconds >= 15;
    final busy = _busy || _confirming;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              active
                  ? 'انتظار بطلب الراكب'
                  : pending
                      ? 'طلب انتظار بانتظار الموافقة'
                      : 'الانتظار أثناء الرحلة',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (active) ...[
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
            ],
            if (pending)
              Text(
                _data?['requestedByMe'] == true
                    ? 'أُرسل الطلب. لا يبدأ الوقت قبل موافقة الطرف الآخر.'
                    : 'راجع الشروط أدناه قبل الموافقة.',
              ),
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
                  'rejected' => 'رُفض طلب الانتظار دون رسوم.',
                  'request_expired' => 'انتهت مهلة الموافقة على الانتظار.',
                  _ => 'انتهى التوقف.'
                },
              ),
            if (stale)
              TextButton(
                onPressed: _refresh,
                child: const Text('بانتظار المزامنة — تحديث الحالة'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_data?['canRequest'] == true)
              OutlinedButton.icon(
                onPressed: busy || stale ? null : () => _action('add'),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('توقف بطلب الراكب'),
              ),
            if (_data?['canDecide'] == true)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy || stale ? null : () => _action('accept'),
                    child: const Text('مراجعة وموافقة'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _action('reject'),
                    child: const Text('رفض'),
                  ),
                ],
              ),
            if (pending && _data?['requestedByMe'] == true)
              TextButton(
                onPressed: busy ? null : () => _action('cancel'),
                child: const Text('سحب طلب الانتظار'),
              ),
            if (active && widget.isDriver)
              FilledButton(
                onPressed: busy ? null : () => _action('update'),
                child: const Text('استئناف الرحلة وإيقاف الانتظار'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }
}
