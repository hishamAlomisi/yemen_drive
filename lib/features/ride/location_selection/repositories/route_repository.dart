import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/config/app_environment.dart';

abstract interface class RouteRepository {
  Future<List<LatLng>> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  });
}

class GoogleRoutesRepository implements RouteRepository {
  GoogleRoutesRepository()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );

  final Dio _dio;

  @override
  Future<List<LatLng>> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final key = AppEnvironment.googleRoutesApiKey.trim().isEmpty
        ? AppEnvironment.googleMapsApiKey
        : AppEnvironment.googleRoutesApiKey;

    if (key.isEmpty) {
      throw const RouteRequestException(
        statusCode: 0,
        message: 'لم يتم تمرير مفتاح Google Routes إلى التطبيق.',
      );
    }

    final response = await _dio.post<Map<String, dynamic>>(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
      data: <String, Object?>{
        'origin': {
          'location': {
            'latLng': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            },
          },
        },
        'destination': {
          'location': {
            'latLng': {
              'latitude': destination.latitude,
              'longitude': destination.longitude,
            },
          },
        },
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
        'polylineQuality': 'HIGH_QUALITY',
        'polylineEncoding': 'ENCODED_POLYLINE',
      },
      options: Options(
        validateStatus: (status) => status != null && status < 500,
        headers: <String, String>{
          'X-Goog-Api-Key': key,
          'X-Goog-FieldMask':
              'routes.polyline.encodedPolyline,routes.distanceMeters,routes.duration',
          if (AppEnvironment.androidCertSha1.isNotEmpty) ...<String, String>{
            'X-Android-Package': AppEnvironment.androidPackageName,
            'X-Android-Cert': AppEnvironment.androidCertSha1,
          },
        },
      ),
    );

    if (response.statusCode != 200) {
      final error = response.data?['error'];
      final message =
          error is Map<String, dynamic> ? _googleErrorMessage(error) : null;
      if (response.statusCode == 403) {
        return _getLegacyDirectionsRoute(
          key: key,
          origin: origin,
          destination: destination,
        );
      }
      throw RouteRequestException(
        statusCode: response.statusCode ?? 0,
        message: message ?? 'Google Routes request was rejected.',
      );
    }

    final routes = response.data?['routes'];
    if (routes is! List<dynamic> || routes.isEmpty) {
      throw const RouteRequestException(
        statusCode: 200,
        message: 'لم تعثر Google على مسار قيادة بين النقطتين.',
      );
    }
    final route = routes.first;
    if (route is! Map<String, dynamic>) {
      throw const RouteRequestException(
        statusCode: 200,
        message: 'صيغة المسار غير صالحة.',
      );
    }
    final polyline = route['polyline'];
    final encoded =
        polyline is Map<String, dynamic> ? polyline['encodedPolyline'] : null;
    if (encoded is! String || encoded.isEmpty) {
      throw const RouteRequestException(
        statusCode: 200,
        message: 'لم يصل خط المسار من Google.',
      );
    }
    return _decodePolyline(encoded);
  }

  Future<List<LatLng>> _getLegacyDirectionsRoute({
    required String key,
    required LatLng origin,
    required LatLng destination,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/directions/json',
      queryParameters: <String, Object?>{
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'language': 'ar',
        'key': key,
      },
      options: Options(
        validateStatus: (status) => status != null && status < 500,
        headers: <String, String>{
          if (AppEnvironment.androidCertSha1.isNotEmpty) ...<String, String>{
            'X-Android-Package': AppEnvironment.androidPackageName,
            'X-Android-Cert': AppEnvironment.androidCertSha1,
          },
        },
      ),
    );
    final data = response.data;
    final status = data?['status']?.toString();
    if (response.statusCode == 200 && status == 'OK') {
      final routes = data?['routes'];
      if (routes is List<dynamic> && routes.isNotEmpty) {
        final route = routes.first;
        if (route is Map<String, dynamic>) {
          final overview = route['overview_polyline'];
          final encoded =
              overview is Map<String, dynamic> ? overview['points'] : null;
          if (encoded is String && encoded.isNotEmpty) {
            return _decodePolyline(encoded);
          }
        }
      }
    }
    final message = data?['error_message']?.toString() ??
        'Directions API returned status: ${status ?? response.statusCode}';
    throw RouteRequestException(
      statusCode: response.statusCode ?? 0,
      message: message,
    );
  }

  String _googleErrorMessage(Map<String, dynamic> error) {
    final parts = <String>[
      if (error['message'] != null) error['message'].toString(),
    ];
    final details = error['details'];
    if (details is List<dynamic>) {
      for (final detail in details) {
        if (detail is! Map<String, dynamic>) continue;
        final reason = detail['reason']?.toString();
        if (reason != null && reason.isNotEmpty) parts.add('Reason: $reason');
        final metadata = detail['metadata'];
        if (metadata is Map<String, dynamic>) {
          final service = metadata['service']?.toString();
          final consumer = metadata['consumer']?.toString();
          if (service != null) parts.add('Service: $service');
          if (consumer != null) parts.add('Consumer: $consumer');
        }
      }
    }
    return parts.isEmpty
        ? 'Google Routes request was rejected.'
        : parts.join('\n');
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      latitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      longitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }
    return points;
  }
}

class RouteRequestException implements Exception {
  const RouteRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'RouteRequestException($statusCode): $message';
}
