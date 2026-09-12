enum RideApiStatus {
  searching,
  driverAssigned,
  driverArriving,
  inProgress,
  completed,
  cancelled,
  unknown;

  static RideApiStatus fromJson(Object? value) {
    final normalized =
        value?.toString().replaceAll(RegExp('[^a-zA-Z]'), '').toLowerCase();
    return switch (normalized) {
      'searching' || 'requested' => RideApiStatus.searching,
      'driverassigned' || 'accepted' => RideApiStatus.driverAssigned,
      'driverarriving' || 'arriving' => RideApiStatus.driverArriving,
      'inprogress' || 'started' => RideApiStatus.inProgress,
      'completed' || 'finished' => RideApiStatus.completed,
      'cancelled' || 'canceled' => RideApiStatus.cancelled,
      _ => RideApiStatus.unknown,
    };
  }
}

class RideGeoPoint {
  const RideGeoPoint({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  factory RideGeoPoint.fromJson(Map<String, Object?> json) => RideGeoPoint(
        latitude: _asDouble(json['latitude'] ?? json['lat']),
        longitude: _asDouble(json['longitude'] ?? json['lng']),
        address: json['address']?.toString() ?? '',
      );

  final double latitude;
  final double longitude;
  final String address;

  Map<String, Object?> toJson() => <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };
}

class RideQuoteRequest {
  const RideQuoteRequest({
    required this.pickup,
    required this.destination,
    required this.serviceKindId,
    required this.serviceCatalogItemId,
  });

  final RideGeoPoint pickup;
  final RideGeoPoint destination;
  final int serviceKindId;
  final int serviceCatalogItemId;

  Map<String, Object?> toJson() => <String, Object?>{
        'pickup': pickup.toJson(),
        'destination': destination.toJson(),
        'serviceKindId': serviceKindId,
        'serviceCatalogItemId': serviceCatalogItemId,
      };
}

class RideVehicleOption {
  const RideVehicleOption({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.etaMinutes,
    required this.seats,
    required this.rating,
    this.imageUrl,
    this.serviceType = '',
    this.serviceKindId,
    this.serviceCatalogItemId,
    this.description = '',
    this.isRecommended = false,
  });

  factory RideVehicleOption.fromJson(Map<String, Object?> json) =>
      RideVehicleOption(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? json['nameAr']?.toString() ?? '',
        category: json['category']?.toString() ??
            json['vehicleType']?.toString() ??
            '',
        price: _asDouble(
          json['price'] ?? json['estimatedFare'] ?? json['basePrice'],
        ),
        etaMinutes: _asInt(json['etaMinutes'] ?? json['arrivalMinutes']),
        seats: _asInt(json['seats'], fallback: 4),
        rating: _asDouble(json['rating']),
        imageUrl: json['imageUrl']?.toString(),
        description: json['description']?.toString() ?? '',
        serviceType: json['serviceType']?.toString() ?? '',
        serviceKindId: _asIntNullable(json['serviceKindId']),
        serviceCatalogItemId: _asIntNullable(json['serviceCatalogItemId'] ?? json['id']),
        isRecommended: json['isRecommended'] == true,
      );

  final String id;
  final String name;
  final String category;
  final double price;
  final int etaMinutes;
  final int seats;
  final double rating;
  final String? imageUrl;
  final String description;
  final String serviceType;
  final int? serviceKindId;
  final int? serviceCatalogItemId;
  final bool isRecommended;
}

class RideQuote {
  const RideQuote({
    required this.id,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.currency,
    required this.vehicles,
  });

  factory RideQuote.fromJson(Map<String, Object?> json) {
    final rawVehicles = json['vehicles'];
    return RideQuote(
      id: (json['id'] ?? json['quoteId'])?.toString() ?? '',
      distanceKm: _asDouble(json['distanceKm'] ?? json['distance']),
      estimatedMinutes: _asInt(
        json['estimatedMinutes'] ?? json['durationMinutes'],
      ),
      currency: json['currency']?.toString() ?? 'SAR',
      vehicles: rawVehicles is List<Object?>
          ? rawVehicles
              .whereType<Map<Object?, Object?>>()
              .map(
                (item) => RideVehicleOption.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList(growable: false)
          : const <RideVehicleOption>[],
    );
  }

  final String id;
  final double distanceKm;
  final int estimatedMinutes;
  final String currency;
  final List<RideVehicleOption> vehicles;
}

class CreateRideRequest {
  const CreateRideRequest({
    required this.quoteId,
    required this.vehicleOptionId,
    required this.paymentMethod,
    this.scheduledAt,
  });

  final String quoteId;
  final String vehicleOptionId;
  final String paymentMethod;
  final DateTime? scheduledAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'quoteId': quoteId,
        'vehicleOptionId': vehicleOptionId,
        'paymentMethod': paymentMethod,
        if (scheduledAt != null)
          'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
      };
}

class RideDriverSummary {
  const RideDriverSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.rating,
    required this.vehicleName,
    required this.plateNumber,
    this.photoUrl,
  });

  factory RideDriverSummary.fromJson(Map<String, Object?> json) =>
      RideDriverSummary(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        rating: _asDouble(json['rating']),
        vehicleName: json['vehicleName']?.toString() ?? '',
        plateNumber: json['plateNumber']?.toString() ?? '',
        photoUrl: json['photoUrl']?.toString(),
      );

  final String id;
  final String name;
  final String phone;
  final double rating;
  final String vehicleName;
  final String plateNumber;
  final String? photoUrl;
}

class RideDetails {
  const RideDetails({
    required this.id,
    required this.status,
    required this.pickup,
    required this.destination,
    required this.fare,
    required this.currency,
    this.driver,
    this.estimatedArrival,
  });

  factory RideDetails.fromJson(Map<String, Object?> json) {
    final driver = json['driver'];
    return RideDetails(
      id: json['id']?.toString() ?? '',
      status: RideApiStatus.fromJson(json['status']),
      pickup: RideGeoPoint.fromJson(_asMap(json['pickup'])),
      destination: RideGeoPoint.fromJson(_asMap(json['destination'])),
      fare: _asDouble(json['fare'] ?? json['total']),
      currency: json['currency']?.toString() ?? 'SAR',
      driver: driver is Map<Object?, Object?>
          ? RideDriverSummary.fromJson(Map<String, Object?>.from(driver))
          : null,
      estimatedArrival: DateTime.tryParse(
        json['estimatedArrival']?.toString() ?? '',
      ),
    );
  }

  final String id;
  final RideApiStatus status;
  final RideGeoPoint pickup;
  final RideGeoPoint destination;
  final double fare;
  final String currency;
  final RideDriverSummary? driver;
  final DateTime? estimatedArrival;
}

class DriverLocationUpdate {
  const DriverLocationUpdate({
    required this.rideId,
    required this.location,
    required this.heading,
    required this.updatedAt,
  });

  factory DriverLocationUpdate.fromJson(Map<String, Object?> json) =>
      DriverLocationUpdate(
        rideId: json['rideId']?.toString() ?? '',
        location: RideGeoPoint.fromJson(_asMap(json['location'])),
        heading: _asDouble(json['heading']),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  final String rideId;
  final RideGeoPoint location;
  final double heading;
  final DateTime updatedAt;
}

Map<String, Object?> _asMap(Object? value) => value is Map<Object?, Object?>
    ? Map<String, Object?>.from(value)
    : <String, Object?>{};

double _asDouble(Object? value, {double fallback = 0}) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

int _asInt(Object? value, {int fallback = 0}) =>
  value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

int? _asIntNullable(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
