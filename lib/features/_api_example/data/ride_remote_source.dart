import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_models.dart';
import '../../../shared/models/ride_models.dart';

/// مثال جاهز لربط تدفق الرحلة مع ASP.NET Web API.
///
/// يمكن حقنه في أي GetX repository أو controller عبر `Get.find<ApiClient>()`.
class RideRemoteSource {
  const RideRemoteSource(this._client);

  final ApiClient _client;

  Future<ApiResult<List<RideVehicleOption>>> getVehicles({
    int? serviceKindId,
  }) async {
    try {
      final response = await _client.dio.get<Object?>(
        ApiEndpoints.vehicles,
        queryParameters: <String, Object?>{
          if (serviceKindId != null) 'serviceKindId': serviceKindId,
        },
      );
      final items = _asList(response.data);
      return ApiSuccess<List<RideVehicleOption>>(
        items
            .whereType<Map<Object?, Object?>>()
            .map(
              (item) =>
                  RideVehicleOption.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false),
      );
    } on DioException catch (error) {
      return ApiFailure<List<RideVehicleOption>>(_client.problemFrom(error));
    } catch (error) {
      return ApiFailure<List<RideVehicleOption>>(_client.problemFrom(error));
    }
  }

  Future<ApiResult<RideQuote>> requestQuote(RideQuoteRequest request) async {
    try {
      final response = await _client.dio.post<Object?>(
        ApiEndpoints.rideQuotes,
        data: request.toJson(),
      );
      return ApiSuccess<RideQuote>(
        RideQuote.fromJson(_asPayload(response.data)),
      );
    } on DioException catch (error) {
      return ApiFailure<RideQuote>(_client.problemFrom(error));
    } catch (error) {
      return ApiFailure<RideQuote>(_client.problemFrom(error));
    }
  }

  Future<ApiResult<RideDetails>> createRide(CreateRideRequest request) async {
    try {
      final response = await _client.dio.post<Object?>(
        ApiEndpoints.rides,
        data: request.toJson(),
      );
      return ApiSuccess<RideDetails>(
        RideDetails.fromJson(_asPayload(response.data)),
      );
    } on DioException catch (error) {
      return ApiFailure<RideDetails>(_client.problemFrom(error));
    } catch (error) {
      return ApiFailure<RideDetails>(_client.problemFrom(error));
    }
  }

  Future<ApiResult<RideDetails>> getRide(String rideId) async {
    try {
      final response = await _client.dio.get<Object?>(
        '${ApiEndpoints.rides}/$rideId',
      );
      return ApiSuccess<RideDetails>(
        RideDetails.fromJson(_asPayload(response.data)),
      );
    } on DioException catch (error) {
      return ApiFailure<RideDetails>(_client.problemFrom(error));
    } catch (error) {
      return ApiFailure<RideDetails>(_client.problemFrom(error));
    }
  }

  Future<ApiResult<DriverLocationUpdate>> getDriverLocation(
    String rideId,
  ) async {
    try {
      final response = await _client.dio.get<Object?>(
        '${ApiEndpoints.rides}/$rideId/tracking',
      );
      return ApiSuccess<DriverLocationUpdate>(
        DriverLocationUpdate.fromJson(_asPayload(response.data)),
      );
    } on DioException catch (error) {
      return ApiFailure<DriverLocationUpdate>(_client.problemFrom(error));
    } catch (error) {
      return ApiFailure<DriverLocationUpdate>(_client.problemFrom(error));
    }
  }

  Future<ApiResult<void>> cancelRide({
    required String rideId,
    required String reason,
  }) async {
    try {
      await _client.dio.post<void>(
        '${ApiEndpoints.rides}/$rideId/cancel',
        data: <String, Object?>{'reason': reason},
      );
      return const ApiSuccess<void>(null);
    } on DioException catch (error) {
      return ApiFailure<void>(_client.problemFrom(error));
    } catch (error) {
      return ApiFailure<void>(_client.problemFrom(error));
    }
  }
}

Map<String, Object?> _asPayload(Object? value) {
  if (value is! Map<Object?, Object?>) return <String, Object?>{};
  final map = Map<String, Object?>.from(value);
  final data = map['data'];
  return data is Map<Object?, Object?> ? Map<String, Object?>.from(data) : map;
}

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) return value;
  if (value is! Map<Object?, Object?>) return const <Object?>[];
  final map = Map<String, Object?>.from(value);
  final nested = map['items'] ?? map['data'];
  return nested is List<Object?> ? nested : const <Object?>[];
}
