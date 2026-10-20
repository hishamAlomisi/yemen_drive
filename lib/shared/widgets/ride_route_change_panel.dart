import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_models.dart';
import '../models/ride_route_change_snapshot.dart';

export '../models/ride_route_change_snapshot.dart' show RideRouteDestination;

/// A quote is confirmed by its owner, then approved by the other participant.
/// Only a server route version change refreshes the actual ride/map/payment.
class RideRouteChangePanel extends StatefulWidget {
  const RideRouteChangePanel({
    required this.rideId,
    required this.selectDestination,
    this.isDriver = false,
    this.onRouteChanged,
    super.key,
  });

  final int rideId;
  final bool isDriver;
  final Future<RideRouteDestination?> Function() selectDestination;
  final Future<void> Function()? onRouteChanged;

  @override
  State<RideRouteChangePanel> createState() => _RideRouteChangePanelState();
}

class _RideRouteChangePanelState extends State<RideRouteChangePanel>
    with WidgetsBindingObserver {
  RideRouteChangeSnapshot? _snapshot;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  bool _loading = false;
  bool _busy = false;
  bool _reviewing = false;
  bool _paused = false;
  bool _syncingRoute = false;
  int _generation = 0;
  int _appliedRouteVersion = 0;
  int _ticks = 0;
  String? _error;
  String? _requestKey;
  String? _lastNotice;
  RideRouteDestination? _quoteDestination;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      if (++_ticks % 5 == 0) unawaited(_refresh());
      if (_snapshot?.request?.isOpen == true) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant RideRouteChangePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rideId == widget.rideId) return;
    ++_generation;
    _snapshot = null;
    _loading = false;
    _busy = false;
    _reviewing = false;
    _syncingRoute = false;
    _appliedRouteVersion = 0;
    _requestKey = null;
    _lastNotice = null;
    _quoteDestination = null;
    _error = null;
    _elapsed.reset();
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (!_paused) unawaited(_refresh());
  }

  bool get _stale => _error != null || _elapsed.elapsed.inSeconds >= 15;
  DateTime get _serverNow => _snapshot!.serverNowUtc.add(_elapsed.elapsed);

  Future<RideRouteChangeSnapshot> _call(
    String operation, {
    int? requestId,
    RideRouteDestination? destination,
  }) async {
    final rideId = widget.rideId;
    final result = await Get.find<ApiClient>().execute<Object?>(
      model: 'RideRouteChangeModel',
      operation: operation,
      data: <String, Object?>{
        'rideId': rideId,
        if (requestId != null) 'requestId': requestId,
        if (destination != null) ...{
          'requestKey': _requestKey,
          'newDestinationLatitude': destination.latitude,
          'newDestinationLongitude': destination.longitude,
          'newDestinationLabel': destination.label.trim(),
        },
      },
    );
    if (result is ApiFailure) {
      throw FormatException(result.problem.detail ?? result.problem.title);
    }
    return RideRouteChangeSnapshot(
      (result as ApiSuccess).data,
      expectedRideId: rideId,
    );
  }

  Future<void> _apply(RideRouteChangeSnapshot value) async {
    setState(() {
      _snapshot = value;
      _error = null;
      _elapsed
        ..reset()
        ..start();
    });
    final request = value.request;
    final notice = request == null ? null : '${request.id}:${request.status}';
    if (notice != _lastNotice) {
      _lastNotice = notice;
      if (request != null &&
          ((request.status == 'pending' && !request.requestedByMe) ||
              request.status == 'accepted' ||
              request.status == 'rejected')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _statusText(
                  request, false, widget.isDriver ? 'الراكب' : 'السائق'),
            ),
          ),
        );
      }
    }
    if (value.routeVersion <= _appliedRouteVersion || _syncingRoute) return;
    _syncingRoute = true;
    final rideId = widget.rideId;
    try {
      await widget.onRouteChanged?.call();
      if (mounted && rideId == widget.rideId) {
        _appliedRouteVersion = value.routeVersion;
      }
    } catch (_) {
      if (mounted && rideId == widget.rideId) {
        setState(
          () => _error = 'تم اعتماد الوجهة. تعذر تحديث الرحلة؛ أعد المزامنة.',
        );
      }
    } finally {
      if (mounted && rideId == widget.rideId) _syncingRoute = false;
    }
  }

  Future<void> _refresh() async {
    if (_loading || _busy || _paused) return;
    _loading = true;
    final generation = _generation;
    try {
      final value = await _call('get');
      if (mounted && generation == _generation) await _apply(value);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'تعذرت مزامنة تغيير الوجهة. تحقق من الاتصال وأعد المحاولة.',
        );
      }
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  Future<void> _selectDestination() async {
    if (_busy || _reviewing || _stale || _snapshot?.canRequest != true) return;
    final rideId = widget.rideId;
    setState(() => _reviewing = true);
    RideRouteDestination? destination;
    try {
      destination = await widget.selectDestination();
    } finally {
      if (mounted && rideId == widget.rideId) {
        setState(() => _reviewing = false);
      }
    }
    if (!mounted || rideId != widget.rideId || destination == null) return;
    if (!destination.isValid) return;
    final previous = _quoteDestination;
    if (previous?.latitude != destination.latitude ||
        previous?.longitude != destination.longitude ||
        previous?.label != destination.label) {
      _requestKey = null;
    }
    _quoteDestination = destination;
    _requestKey ??= _newRequestKey();
    final quoted = await _mutate('quote', destination: destination);
    if (quoted && mounted && _snapshot?.request?.canConfirm == true) {
      await _review(_snapshot!.request!);
    }
  }

  static String _newRequestKey() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<bool> _mutate(
    String operation, {
    int? requestId,
    RideRouteDestination? destination,
  }) async {
    if (_busy) return false;
    final generation = ++_generation;
    _loading = false;
    setState(() => _busy = true);
    var succeeded = false;
    try {
      final value = await _call(
        operation,
        requestId: requestId,
        destination: destination,
      );
      if (!mounted || generation != _generation) return false;
      await _apply(value);
      if (operation == 'quote') _requestKey = null;
      succeeded = true;
    } catch (error) {
      if (mounted && generation == _generation) {
        final message = error is FormatException
            ? error.message
            : 'تعذر تنفيذ الطلب. حدّث الحالة وحاول مجددًا.';
        setState(() => _error = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        if (!succeeded) unawaited(_refresh());
      }
    }
    return succeeded;
  }

  Future<void> _review(RideRouteChangeRequest request) async {
    if (_reviewing || _busy || _stale) return;
    final rideId = widget.rideId;
    final operation =
        request.canConfirm && request.requestedByMe ? 'add' : 'accept';
    if (operation == 'accept' &&
        (!request.canDecide || request.requestedByMe)) {
      return;
    }
    setState(() => _reviewing = true);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فاتورة تغيير الوجهة'),
        content: SingleChildScrollView(
          child: RideRouteChangeInvoiceView(request: request),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              operation == 'add'
                  ? 'أوافق وأرسل الطلب'
                  : 'أوافق على الوجهة والفاتورة',
            ),
          ),
        ],
      ),
    );
    if (!mounted || rideId != widget.rideId) return;
    setState(() => _reviewing = false);
    if (approved != true) return;
    final current = _snapshot?.request;
    if (_stale ||
        current == null ||
        current.id != request.id ||
        current.status != request.status ||
        current.isExpired(_serverNow) ||
        current.invoice.fingerprint != request.invoice.fingerprint ||
        (operation == 'add' ? !current.canConfirm : !current.canDecide)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تغير العرض أو انتهت صلاحيته. اطلب فاتورة جديدة.'),
        ),
      );
      unawaited(_refresh());
      return;
    }
    await _mutate(operation, requestId: request.id);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return _error == null
          ? const SizedBox.shrink()
          : TextButton(onPressed: _refresh, child: Text(_error!));
    }
    final request = snapshot.request;
    final expired = request?.isExpired(_serverNow) == true;
    final blocked = _busy || _reviewing || _stale || expired;
    final other = widget.isDriver ? 'الراكب' : 'السائق';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تغيير وجهة الرحلة',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (snapshot.unavailableReason?.trim().isNotEmpty == true)
              Text(snapshot.unavailableReason!),
            if (request != null) ...[
              Text(_statusText(request, expired, other)),
              Text(request.destination.label),
              Text(
                'الإجمالي المقترح: ${request.invoice['newTotal'].toStringAsFixed(0)} ر.ي',
              ),
              if (request.isOpen && !expired)
                Text(
                  'صلاحية العرض: ${request.expiresAtUtc!.difference(_serverNow).inSeconds.clamp(0, 120)} ثانية',
                ),
              if (request.isOpen)
                const Text(
                  'تستمر الرحلة بوجهتها الحالية حتى موافقة الطرف الآخر. يُعاد التسعير عند تحرك السيارة أو انتهاء العرض.',
                ),
              if ((request.canConfirm && request.requestedByMe) ||
                  (request.canDecide && !request.requestedByMe))
                FilledButton(
                  onPressed: blocked ? null : () => _review(request),
                  child: const Text('مراجعة الفاتورة والموافقة'),
                ),
              if (request.isOpen && request.requestedByMe)
                TextButton(
                  onPressed: _busy || _reviewing
                      ? null
                      : () => _mutate('cancel', requestId: request.id),
                  child: const Text('سحب طلب تغيير الوجهة'),
                ),
              if (request.canDecide && !request.requestedByMe)
                TextButton(
                  onPressed: blocked
                      ? null
                      : () => _mutate('reject', requestId: request.id),
                  child: const Text('رفض تغيير الوجهة'),
                ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_stale || expired)
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('تحديث حالة العرض'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (snapshot.canRequest)
              OutlinedButton.icon(
                onPressed:
                    _busy || _reviewing || _stale ? null : _selectDestination,
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('اختيار وجهة جديدة وعرض الفاتورة'),
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(
    RideRouteChangeRequest request,
    bool expired,
    String other,
  ) {
    if (expired) return 'انتهت صلاحية العرض. حدّث الحالة واطلب فاتورة جديدة.';
    return switch (request.status) {
      'quoted' => 'راجع الفاتورة قبل إرسال الطلب إلى $other.',
      'pending' => request.requestedByMe
          ? 'بانتظار موافقة $other.'
          : 'طلب $other تغيير الوجهة. راجع الفاتورة.',
      'accepted' => 'تمت الموافقة على الوجهة والفاتورة الجديدة.',
      'rejected' => 'رُفض الطلب. تستمر الرحلة بالوجهة الحالية.',
      'cancelled' => 'سُحب طلب تغيير الوجهة.',
      _ => 'انتهت صلاحية العرض. اطلب فاتورة جديدة.',
    };
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }
}

class RideRouteChangeInvoiceView extends StatelessWidget {
  const RideRouteChangeInvoiceView({required this.request, super.key});
  final RideRouteChangeRequest request;

  @override
  Widget build(BuildContext context) {
    final invoice = request.invoice;
    Widget money(String title, String field) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('$title: ${invoice[field].toStringAsFixed(0)} ر.ي'),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('الوجهة الجديدة: ${request.destination.label}'),
        const Divider(),
        money('الإجمالي السابق', 'previousTotal'),
        Text(
          'المسافة المنجزة: ${(invoice['completedDistanceMeters'] / 1000).toStringAsFixed(2)} كم',
        ),
        money('أجرة الجزء المنجز', 'completedFare'),
        money('رسوم الخدمة الأصلية', 'originalServiceFee'),
        money('رسوم التغييرات السابقة', 'previousRouteChangeFees'),
        money('رسوم تغيير الوجهة', 'routeChangeFee'),
        Text(
          'المسافة إلى الوجهة الجديدة: ${(invoice['newDistanceMeters'] / 1000).toStringAsFixed(2)} كم',
        ),
        Text(
          'المدة المتوقعة: ${(invoice['newDurationSeconds'] / 60).ceil()} دقيقة',
        ),
        money('أجرة المسار الجديد', 'newRouteFare'),
        money('الانتظار المحتسب', 'waitingFee'),
        const Divider(),
        money('الإجمالي الجديد', 'newTotal'),
        money('الفرق عن السابق', 'difference'),
        const SizedBox(height: 8),
        const Text(
          'لن تتغير الوجهة أو الأجرة إلا بعد موافقة الطرف الآخر. إذا تغير موقع السيارة أو انتهت المهلة، يلزم عرض جديد.',
        ),
      ],
    );
  }
}
