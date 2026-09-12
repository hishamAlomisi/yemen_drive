import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/config/app_environment.dart';

class LocationSearchResult {
  const LocationSearchResult({
    required this.title,
    required this.formattedAddress,
    required this.location,
    this.street = '',
  });

  final String title;
  final String formattedAddress;
  final String street;
  final LatLng location;
}

class NoInternetException implements Exception {
  const NoInternetException();
}

abstract interface class LocationSearchRepository {
  Future<List<LocationSearchResult>> search(String query);
  Future<LocationSearchResult?> reverseGeocode(LatLng point);
}

class GoogleLocationSearchRepository implements LocationSearchRepository {
  GoogleLocationSearchRepository()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

  final Dio _dio;

  String get _placesKey => AppEnvironment.googlePlacesApiKey;
  String get _geocodingKey => AppEnvironment.googleGeocodingApiKey;

  @override
  Future<List<LocationSearchResult>> search(String query) async {
    if (query.trim().length < 2 || _placesKey.isEmpty) return const [];
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://places.googleapis.com/v1/places:searchText',
        data: <String, Object?>{
          'textQuery': query.trim(),
          'languageCode': 'ar',
          'regionCode': 'YE',
          'maxResultCount': 8,
        },
        options: Options(
          headers: <String, String>{
            'X-Goog-Api-Key': _placesKey,
            'X-Goog-FieldMask':
                'places.displayName,places.formattedAddress,places.location,places.addressComponents',
            ..._androidRestrictionHeaders,
          },
        ),
      );
      final places = response.data?['places'];
      if (places is! List<dynamic>) return const [];
      return places.whereType<Map<String, dynamic>>().map(_fromPlace).toList();
    } on DioException catch (error) {
      if (_isNetworkError(error)) throw const NoInternetException();
      rethrow;
    }
  }

  @override
  Future<LocationSearchResult?> reverseGeocode(LatLng point) async {
    if (_geocodingKey.isEmpty) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: <String, Object?>{
          'latlng': '${point.latitude},${point.longitude}',
          'language': 'ar',
          'key': _geocodingKey,
        },
        options: Options(headers: _androidRestrictionHeaders),
      );
      final results = response.data?['results'];
      if (results is! List<dynamic> || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;
      return LocationSearchResult(
        title: _component(
          first,
          const [
            'premise',
            'point_of_interest',
            'establishment',
            'neighborhood',
          ],
        ),
        street: _component(first, const ['route']),
        formattedAddress: first['formatted_address']?.toString() ?? '',
        location: point,
      );
    } on DioException catch (error) {
      if (_isNetworkError(error)) throw const NoInternetException();
      rethrow;
    }
  }

  LocationSearchResult _fromPlace(Map<String, dynamic> place) {
    final location = place['location'] as Map<String, dynamic>?;
    final displayName = place['displayName'] as Map<String, dynamic>?;
    return LocationSearchResult(
      title: displayName?['text']?.toString() ?? 'موقع',
      formattedAddress: place['formattedAddress']?.toString() ?? '',
      street: _component(place, const ['route']),
      location: LatLng(
        (location?['latitude'] as num?)?.toDouble() ?? 0,
        (location?['longitude'] as num?)?.toDouble() ?? 0,
      ),
    );
  }

  String _component(Map<String, dynamic> value, List<String> wanted) {
    final components =
        value['addressComponents'] ?? value['address_components'];
    if (components is! List<dynamic>) return '';
    for (final component in components.whereType<Map<String, dynamic>>()) {
      final types = component['types'];
      if (types is List<dynamic> && types.any(wanted.contains)) {
        return component['longText']?.toString() ??
            component['long_name']?.toString() ??
            '';
      }
    }
    return '';
  }

  bool _isNetworkError(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout;

  Map<String, String> get _androidRestrictionHeaders =>
      AppEnvironment.androidCertSha1.isEmpty
          ? const <String, String>{}
          : <String, String>{
              'X-Android-Package': AppEnvironment.androidPackageName,
              'X-Android-Cert': AppEnvironment.androidCertSha1,
            };
}
