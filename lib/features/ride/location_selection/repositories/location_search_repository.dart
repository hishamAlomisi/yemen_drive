import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

class LocationSearchResult {
  const LocationSearchResult({
    required this.title,
    required this.formattedAddress,
    required this.location,
    this.street = '',
    this.area = '',
  });

  final String title;
  final String formattedAddress;
  final String street;
  final String area;
  final LatLng location;
}

class NoInternetException implements Exception {
  const NoInternetException();
}

abstract interface class LocationSearchRepository {
  Future<List<LocationSearchResult>> search(String query);
  Future<LocationSearchResult?> reverseGeocode(LatLng point);
}

/// Places and reverse-geocoding are proxied by YemenDrive API so provider
/// keys and provider-specific response data do not reach the mobile client.
class ApiLocationSearchRepository implements LocationSearchRepository {
  ApiLocationSearchRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<LocationSearchResult>> search(String query) async {
    if (query.trim().length < 2) return const [];
    final result = await _client.execute<Object?>(
      model: 'MapLocationSearchModel',
      operation: 'search',
      data: <String, Object?>{'query': query.trim()},
    );
    if (result is ApiFailure<Object?>) _throwForFailure(result);
    if (result is! ApiSuccess<Object?> || result.data is! List) return const [];
    return (result.data as List)
        .whereType<Map<Object?, Object?>>()
        .map((item) => _fromJson(Map<Object?, Object?>.from(item)))
        .where(
          (item) => item.location.latitude != 0 || item.location.longitude != 0,
        )
        .toList(growable: false);
  }

  @override
  Future<LocationSearchResult?> reverseGeocode(LatLng point) async {
    final result = await _client.execute<Object?>(
      model: 'MapLocationSearchModel',
      operation: 'report',
      data: <String, Object?>{
        'latitude': point.latitude,
        'longitude': point.longitude,
      },
    );
    if (result is ApiFailure<Object?>) _throwForFailure(result);
    if (result is! ApiSuccess<Object?> || result.data is! Map) return null;
    return _fromJson(Map<Object?, Object?>.from(result.data as Map));
  }

  Never _throwForFailure(ApiFailure<Object?> failure) {
    if (failure.problem.code == 'network_error') {
      throw const NoInternetException();
    }
    final detail = failure.problem.detail?.trim();
    throw LocationSearchRequestException(
      detail == null || detail.isEmpty ? failure.problem.title : detail,
      status: failure.problem.status,
      code: failure.problem.code,
    );
  }

  LocationSearchResult _fromJson(Map<Object?, Object?> data) =>
      LocationSearchResult(
        title: '${data['title'] ?? 'موقع'}',
        formattedAddress: '${data['formattedAddress'] ?? ''}',
        street: '${data['street'] ?? ''}',
        area: '${data['area'] ?? ''}',
        location: LatLng(
          (data['latitude'] as num?)?.toDouble() ?? 0,
          (data['longitude'] as num?)?.toDouble() ?? 0,
        ),
      );
}

class LocationSearchRequestException implements Exception {
  const LocationSearchRequestException(
    this.message, {
    this.status = 0,
    this.code,
  });

  final String message;

  final int status;

  final String? code;

  bool get requiresAuthentication {
    final normalizedCode = code?.toLowerCase() ?? '';
    final normalizedMessage = message.toLowerCase();
    return status == 401 ||
        normalizedCode.contains('unauth') ||
        normalizedCode.contains('authentication') ||
        normalizedCode.contains('login') ||
        normalizedMessage.contains('تسجيل الدخول') ||
        normalizedMessage.contains('سجل الدخول') ||
        normalizedMessage.contains('login required') ||
        normalizedMessage.contains('authentication required') ||
        normalizedMessage.contains('not authenticated') ||
        normalizedMessage.contains('must be logged');
  }

  @override
  String toString() => message;
}
