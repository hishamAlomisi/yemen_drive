import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

abstract interface class RouteRepository {
  Future<DrivingRoute> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  });
}

class DrivingRoute {
  const DrivingRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;
}

/// Gets routing data exclusively through YemenDrive API. Google Routes keys
/// are server credentials and must never be shipped inside the mobile APK.
class ApiRoutesRepository implements RouteRepository {
  ApiRoutesRepository(this._client);

  final ApiClient _client;

  @override
  Future<DrivingRoute> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final result = await _client.execute<Object?>(
      model: 'MapRouteQuoteModel',
      operation: 'report',
      data: <String, Object?>{
        'originLatitude': origin.latitude,
        'originLongitude': origin.longitude,
        'destinationLatitude': destination.latitude,
        'destinationLongitude': destination.longitude,
      },
    );
    if (result is ApiFailure<Object?>) {
      throw RouteRequestException(
        statusCode: result.problem.status,
        message: result.problem.title,
      );
    }
    if (result is! ApiSuccess<Object?> || result.data is! Map) {
      throw const RouteRequestException(
        statusCode: 0,
        message: 'لم تصل بيانات المسار من الخادم.',
      );
    }
    final data = Map<Object?, Object?>.from(result.data as Map);
    final encoded = data['encodedPolyline']?.toString();
    if (encoded == null || encoded.isEmpty) {
      throw const RouteRequestException(
        statusCode: 0,
        message: 'لم يصل خط المسار من الخادم.',
      );
    }
    final distanceMeters = (data['distanceMeters'] as num?)?.toInt();
    final durationSeconds = (data['durationSeconds'] as num?)?.toInt();
    if (distanceMeters == null ||
        durationSeconds == null ||
        distanceMeters <= 0 ||
        durationSeconds < 0) {
      throw const RouteRequestException(
        statusCode: 0,
        message: 'لم تصل مسافة أو مدة المسار من الخادم.',
      );
    }
    return DrivingRoute(
      points: _decodePolyline(encoded),
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
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
        if (index >= encoded.length) {
          throw const RouteRequestException(
            statusCode: 0,
            message: 'صيغة خط المسار غير صالحة.',
          );
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      latitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      shift = 0;
      result = 0;
      do {
        if (index >= encoded.length) {
          throw const RouteRequestException(
            statusCode: 0,
            message: 'صيغة خط المسار غير صالحة.',
          );
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      longitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }
    if (points.length < 2) {
      throw const RouteRequestException(
        statusCode: 0,
        message: 'خط المسار غير مكتمل.',
      );
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
