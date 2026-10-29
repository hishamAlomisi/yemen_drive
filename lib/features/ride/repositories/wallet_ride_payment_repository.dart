import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../models/wallet_ride_payment.dart';

abstract class WalletRidePaymentRepository {
  Future<ApiResult<WalletRidePayment?>> getCurrent(String rideId);
  Future<ApiResult<WalletRidePayment?>> start(String rideId, int methodId);
  Future<ApiResult<WalletRidePayment?>> confirm(
      String rideId, String paymentId, bool approved);
  Future<ApiResult<WalletRidePayment?>> complete(
      String rideId, String paymentId, String code);
}

class ApiWalletRidePaymentRepository implements WalletRidePaymentRepository {
  ApiWalletRidePaymentRepository(this.api);
  final ApiClient api;

  String _path(String rideId) =>
      'rides/${Uri.encodeComponent(rideId)}/wallet-payment';

  @override
  Future<ApiResult<WalletRidePayment?>> getCurrent(String rideId) =>
      _request(_path(rideId));

  @override
  Future<ApiResult<WalletRidePayment?>> start(String rideId, int methodId) =>
      _request(_path(rideId), data: {'paymentMethodId': methodId});

  @override
  Future<ApiResult<WalletRidePayment?>> confirm(
          String rideId, String paymentId, bool approved) =>
      _request('${_path(rideId)}/${Uri.encodeComponent(paymentId)}/confirm',
          data: {'approved': approved});

  @override
  Future<ApiResult<WalletRidePayment?>> complete(
          String rideId, String paymentId, String code) =>
      _request('${_path(rideId)}/${Uri.encodeComponent(paymentId)}/complete',
          data: {'code': code});

  Future<ApiResult<WalletRidePayment?>> _request(String path,
      {Map<String, Object?>? data}) async {
    try {
      final response = await api.dio.request<Object?>(path,
          data: data,
          options: Options(
            method: data == null ? 'GET' : 'POST',
            receiveTimeout: const Duration(seconds: 75),
          ));
      final body = response.data;
      if (body is! Map) throw const FormatException();
      final json = Map<String, Object?>.from(body);
      if (json['success'] != true) {
        return ApiFailure(ApiProblemDetails.fromJson(json,
            fallbackStatus: response.statusCode));
      }
      final payload = json['data'];
      if (payload == null && data == null) return const ApiSuccess(null);
      if (payload is! Map) throw const FormatException();
      return ApiSuccess(
          WalletRidePayment.fromJson(Map<String, Object?>.from(payload)));
    } catch (error) {
      return ApiFailure(api.problemFrom(error));
    }
  }
}
