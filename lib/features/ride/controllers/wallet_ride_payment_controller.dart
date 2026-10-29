import 'dart:async';

import 'package:get/get.dart';

import '../../../core/network/api_models.dart';
import '../models/wallet_ride_payment.dart';
import '../repositories/wallet_ride_payment_repository.dart';

/// The server owns the transaction and its retry policy. A transport error never
/// becomes a failed payment and never causes another withdrawal to be submitted.
class WalletRidePaymentController {
  WalletRidePaymentController(this.repository, {this.onSucceeded});

  final WalletRidePaymentRepository repository;
  final void Function(WalletRidePayment payment)? onSucceeded;
  final Rxn<WalletRidePayment> payment = Rxn<WalletRidePayment>();
  final RxBool busy = false.obs;
  final RxBool stateKnown = false.obs;
  final RxString error = ''.obs;
  String? _rideId;
  int _generation = 0;
  bool _disposed = false;
  Timer? _poll;
  String? _notifiedPayment;
  String _businessError = '';

  bool get locksOtherMethods =>
      busy.value ||
      !stateKnown.value ||
      (payment.value?.locksOtherMethods ?? false);

  bool get canStart => !locksOtherMethods;

  Future<void> refresh(String rideId) async {
    if (_disposed) return;
    if (_rideId != rideId) {
      _rideId = rideId;
      _generation++;
      _poll?.cancel();
      payment.value = null;
      stateKnown.value = false;
      busy.value = false;
      error.value = '';
      _businessError = '';
      _notifiedPayment = null;
    }
    if (busy.value) return;
    await _perform(() => repository.getCurrent(rideId), isMutation: false);
  }

  Future<void> start(String rideId, int methodId) async {
    if (_disposed || busy.value) return;
    // Always recover before submitting; re-opening a page cannot create a new
    // payment while the previous phone or network request is still in flight.
    await refresh(rideId);
    if (!canStart || _rideId != rideId) return;
    await _perform(() => repository.start(rideId, methodId));
  }

  Future<void> confirm(bool approved) async {
    final current = payment.value;
    if (_disposed ||
        busy.value ||
        !stateKnown.value ||
        current == null ||
        !current.awaitingConfirmation ||
        (approved && !current.customerIsProviderVerified)) return;
    await _perform(
        () => repository.confirm(current.rideId, current.id, approved));
  }

  Future<void> complete(String code) async {
    final current = payment.value;
    if (_disposed ||
        busy.value ||
        !stateKnown.value ||
        current == null ||
        !current.awaitingCode ||
        code.trim().isEmpty) return;
    await _perform(
        () => repository.complete(current.rideId, current.id, code.trim()));
  }

  Future<void> _perform(
      Future<ApiResult<WalletRidePayment?>> Function() request,
      {bool isMutation = true}) async {
    final generation = _generation;
    busy.value = true;
    // A status refresh must not erase a provider rejection while the customer
    // is reading it. A new explicit action starts a new message lifecycle.
    if (isMutation) _businessError = '';
    error.value = _businessError;
    _poll?.cancel();
    try {
      final result = await request();
      if (!_current(generation)) return;
      if (result is ApiSuccess<WalletRidePayment?>) {
        _accept(result.data);
      } else if (result is ApiFailure<WalletRidePayment?>) {
        final reason = (result.problem.detail ?? result.problem.title).trim();
        if (isMutation &&
            result.problem.status != 0 &&
            result.problem.code != 'network_error') {
          _businessError = reason;
        }
        _showError(reason);
        // Reconcile after any failed mutation response. The provider may have
        // accepted it even when the response did not reach this device.
        stateKnown.value = false;
        if (isMutation && _rideId != null) {
          final recovered = await repository.getCurrent(_rideId!);
          if (!_current(generation)) return;
          if (recovered is ApiSuccess<WalletRidePayment?>) {
            _accept(recovered.data);
          }
        }
      }
    } catch (_) {
      if (!_current(generation)) return;
      stateKnown.value = false;
      _showError('تعذر التحقق من حالة الدفع. حدّث الحالة قبل المتابعة.');
    } finally {
      if (_current(generation)) {
        busy.value = false;
        if (payment.value?.processing == true && _rideId != null) {
          _poll = Timer(const Duration(seconds: 3), () => refresh(_rideId!));
        }
      }
    }
  }

  void _accept(WalletRidePayment? value) {
    if (value != null && value.rideId != _rideId) {
      stateKnown.value = false;
      error.value = 'تعذر مطابقة عملية الدفع مع الرحلة الحالية.';
      return;
    }
    final previousId = payment.value?.id;
    if (previousId != null && value != null && previousId != value.id) {
      _businessError = '';
    }
    payment.value = value;
    stateKnown.value = true;
    error.value = _businessError;
    if (value?.succeeded == true) {
      _businessError = '';
      error.value = '';
      if (_notifiedPayment != value!.id) {
        _notifiedPayment = value.id;
        onSucceeded?.call(value);
      }
    }
  }

  void _showError(String message) {
    error.value = <String>{_businessError, message}
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void dispose() {
    _disposed = true;
    _generation++;
    _poll?.cancel();
  }
}
