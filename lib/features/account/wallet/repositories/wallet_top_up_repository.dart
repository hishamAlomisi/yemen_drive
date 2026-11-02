import 'package:get_storage/get_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../ride/models/wallet_ride_payment.dart';
import '../../../ride/repositories/wallet_ride_payment_repository.dart';

class WalletTopUpRepository implements WalletRidePaymentRepository {
  WalletTopUpRepository(ApiClient api, int userId, {GetStorage? store})
      : transport = ApiWalletRidePaymentRepository(api),
        storage = store ?? GetStorage(),
        storageKey = 'wallet-top-up-request-$userId';
  final ApiWalletRidePaymentRepository transport;
  final String storageKey;
  final GetStorage storage;
  String? _invoiceId;
  double amount = 0;
  String? _reference;
  bool _terminal = false;
  Future<void> clearFinished() async {
    if (_invoiceId != null) {
      _invoiceId = null;
      _reference = null;
      _terminal = false;
      return;
    }
    if (_terminal) {
      await storage.remove(storageKey);
      _reference = null;
      _terminal = false;
      _invoiceId = null;
    }
  }

  Future<ApiResult<WalletRidePayment?>> getById(String id) async {
    final result = await transport.request('wallet/top-ups/$id');
    if (result is ApiSuccess<WalletRidePayment?> &&
        result.data?.succeeded == true) {
      _invoiceId = id;
    }
    return result;
  }

  @override
  Future<ApiResult<WalletRidePayment?>> getCurrent(String rideId) async {
    if (_invoiceId != null) {
      return transport.request('wallet/top-ups/$_invoiceId');
    }
    final saved = storage.read<Map<String, dynamic>>(storageKey);
    var result = await transport.request('wallet/top-ups/current');
    if (result is ApiSuccess<WalletRidePayment?> &&
        result.data == null &&
        saved != null) {
      if (saved['id'] != null) {
        result = await transport.request('wallet/top-ups/${saved['id']}');
      } else if (saved['requestId'] != null)
        result = await transport
            .request('wallet/top-ups/by-reference/${saved['requestId']}');
    }
    await _remember(result);
    return result;
  }

  Future<void> _remember(ApiResult<WalletRidePayment?> result) async {
    if (result is! ApiSuccess<WalletRidePayment?>) return;
    final operation = result.data;
    if (operation == null) return;
    _terminal = operation.canStartAnother || operation.succeeded;
    _reference = operation.requestId;
    await storage.write(storageKey, {
      'id': operation.id,
      'requestId': operation.requestId,
      'amount': operation.amount,
      'methodId': operation.paymentMethodId,
    });
  }

  @override
  Future<ApiResult<WalletRidePayment?>> start(
    String rideId,
    int methodId,
  ) async {
    final saved = storage.read<Map<String, dynamic>>(storageKey);
    _reference =
        _terminal ? null : _reference ?? saved?['requestId']?.toString();
    _reference ??= const Uuid().v4();
    _terminal = false;
    // Save before HTTP dispatch so a closed app can resume the same reference.
    await storage.write(
      storageKey,
      {'requestId': _reference, 'amount': amount, 'methodId': methodId},
    );
    final result = await transport.request(
      'wallet/top-ups',
      data: {
        'paymentMethodId': methodId,
        'amount': amount,
        'requestId': _reference,
      },
    );
    await _remember(result);
    return result;
  }

  @override
  Future<ApiResult<WalletRidePayment?>> confirm(
    String rideId,
    String paymentId,
    bool approved,
  ) async {
    final result = await transport.request(
      'wallet/top-ups/$paymentId/confirm',
      data: {'approved': approved},
    );
    await _remember(result);
    return result;
  }

  @override
  Future<ApiResult<WalletRidePayment?>> complete(
    String rideId,
    String paymentId,
    String code,
  ) async {
    final result = await transport
        .request('wallet/top-ups/$paymentId/complete', data: {'code': code});
    await _remember(result);
    return result;
  }
}
