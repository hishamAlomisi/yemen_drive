enum RideServiceType { transport, delivery }

enum RideVehicleType { car, bike, cycle, taxi }

enum NegotiationStatus { idle, quoting, ready, searching, accepted, cancelled }

enum DriverOfferStatus { pending, accepted, rejected, expired }

class RideCoordinate {
  const RideCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  Map<String, double> toJson() => <String, double>{
        'latitude': latitude,
        'longitude': longitude,
      };
}

class RideQuote {
  const RideQuote({
    required this.suggestedPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.priceStep,
    this.serviceFee = 0,
    required this.currency,
  });

  final double suggestedPrice;
  final double minPrice;
  final double maxPrice;
  final double priceStep;
  final double serviceFee;
  final String currency;

  Map<String, Object?> toJson() => <String, Object?>{
        'suggestedPrice': suggestedPrice,
        'minPrice': minPrice,
        'maxPrice': maxPrice,
        'priceStep': priceStep,
        'currency': currency,
      };
}

class RideRequestDraft {
  const RideRequestDraft({
    required this.pickup,
    required this.destination,
    required this.pickupCoordinate,
    required this.destinationCoordinate,
    required this.serviceKindId,
    required this.serviceCatalogItemId,
    this.customerId,
    required this.offeredPrice,
    this.pickupAddress = '',
    this.destinationAddress = '',
    this.destinationAddressName = '',
    this.destinationStreet = '',
    this.destinationDetails = '',
    this.routeDistanceMeters,
    this.routeDurationSeconds,
    this.idempotencyKey,
  });

  final String pickup;
  final String destination;
  final RideCoordinate pickupCoordinate;
  final RideCoordinate destinationCoordinate;
  final int serviceKindId;
  final int serviceCatalogItemId;
  final int? customerId;
  final double offeredPrice;
  final String pickupAddress;
  final String destinationAddress;
  final String destinationAddressName;
  final String destinationStreet;
  final String destinationDetails;
  final int? routeDistanceMeters;
  final int? routeDurationSeconds;
  final String? idempotencyKey;

  Map<String, Object?> toJson() => <String, Object?>{
        'pickup': pickup,
        'destination': destination,
        'pickupCoordinate': pickupCoordinate.toJson(),
        'destinationCoordinate': destinationCoordinate.toJson(),
        'serviceKindId': serviceKindId,
        'serviceCatalogItemId': serviceCatalogItemId,
        'offeredPrice': offeredPrice,
        'pickupAddress': pickupAddress,
        'destinationAddress': destinationAddress,
        'destinationAddressName': destinationAddressName,
        'destinationStreet': destinationStreet,
        'destinationDetails': destinationDetails,
        if (routeDistanceMeters != null)
          'routeDistanceMeters': routeDistanceMeters,
        if (routeDurationSeconds != null)
          'routeDurationSeconds': routeDurationSeconds,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      };
}

class NearbyDriver {
  const NearbyDriver({
    required this.id,
    required this.name,
    required this.location,
    required this.photoUrl,
    required this.vehicleType,
    required this.rating,
    this.vehicleModel = '',
    this.plateNumber = '',
    this.completedTrips = 0,
    this.heading,
    this.isAvailable = true,
  });

  final String id;
  final String name;
  final RideCoordinate location;
  final String photoUrl;
  final RideVehicleType vehicleType;
  final double rating;
  final String vehicleModel;
  final String plateNumber;
  final int completedTrips;
  final double? heading;
  final bool isAvailable;
}

class DriverTrackingSnapshot {
  const DriverTrackingSnapshot({
    required this.driverId,
    required this.location,
    required this.updatedAt,
    this.heading,
  });

  final String driverId;
  final RideCoordinate location;
  final DateTime updatedAt;
  final double? heading;
}

class DriverOffer {
  const DriverOffer({
    required this.id,
    required this.driverName,
    required this.vehicleSummary,
    required this.price,
    required this.rating,
    required this.etaMinutes,
    this.status = DriverOfferStatus.pending,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String driverName;
  final String vehicleSummary;
  final double price;
  final double rating;
  final int etaMinutes;
  final DriverOfferStatus status;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  DriverOffer copyWith({
    DriverOfferStatus? status,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) =>
      DriverOffer(
        id: id,
        driverName: driverName,
        vehicleSummary: vehicleSummary,
        price: price,
        rating: rating,
        etaMinutes: etaMinutes,
        status: status ?? this.status,
        expiresAt: expiresAt ?? this.expiresAt,
        createdAt: createdAt ?? this.createdAt,
      );
}

class RideVehicle {
  const RideVehicle({
    required this.id,
    required this.name,
    required this.type,
    this.serviceKindId,
    this.serviceCatalogItemId,
    this.category = '',
    required this.arrivalMinutes,
    required this.price,
    required this.rating,
    required this.seats,
    required this.description,
    this.imageAsset,
    this.isRecommended = false,
  });

  final String id;
  final String name;
  final RideVehicleType type;
  final int? serviceKindId;
  final int? serviceCatalogItemId;
  final String category;
  final int arrivalMinutes;
  final double price;
  final double rating;
  final int seats;
  final String description;
  final String? imageAsset;
  final bool isRecommended;
}

class RideNotificationItem {
  const RideNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.kind,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;
  final String timeLabel;
  final String kind;
  final bool isRead;

  RideNotificationItem copyWith({bool? isRead}) => RideNotificationItem(
        id: id,
        title: title,
        body: body,
        timeLabel: timeLabel,
        kind: kind,
        isRead: isRead ?? this.isRead,
      );
}

class RecentPlace {
  const RecentPlace({
    required this.title,
    required this.address,
    required this.kind,
    required this.latitude,
    required this.longitude,
  });

  final String title;
  final String address;
  final String kind;
  final double latitude;
  final double longitude;
}

class RideChatMessage {
  const RideChatMessage({
    required this.text,
    required this.timeLabel,
    required this.isMine,
  });

  final String text;
  final String timeLabel;
  final bool isMine;
}

const List<RideVehicle> demoRideVehicles = <RideVehicle>[
  RideVehicle(
    id: 'economy-1',
    name: 'إيزي اقتصادي',
    type: RideVehicleType.car,
    imageAsset: 'assets/images/vehicles/car.jpg',
    arrivalMinutes: 3,
    price: 2400,
    rating: 4.9,
    seats: 4,
    description: 'رحلة يومية مريحة بأفضل سعر.',
    isRecommended: true,
  ),
  RideVehicle(
    id: 'comfort-1',
    name: 'إيزي مريح',
    type: RideVehicleType.car,
    imageAsset: 'assets/images/vehicles/car.jpg',
    arrivalMinutes: 5,
    price: 3200,
    rating: 4.8,
    seats: 4,
    description: 'سيارة واسعة وسائق بتقييم مرتفع.',
  ),
  RideVehicle(
    id: 'taxi-1',
    name: 'تاكسي المدينة',
    type: RideVehicleType.taxi,
    imageAsset: 'assets/images/vehicles/taxi.png',
    arrivalMinutes: 4,
    price: 2800,
    rating: 4.7,
    seats: 4,
    description: 'تاكسي مرخّص متاح بالقرب منك.',
  ),
  RideVehicle(
    id: 'bike-1',
    name: 'دراجة سريعة',
    type: RideVehicleType.bike,
    imageAsset: 'assets/images/vehicles/delivery_scooter.jpg',
    arrivalMinutes: 2,
    price: 1500,
    rating: 4.8,
    seats: 1,
    description: 'الخيار الأسرع للرحلات الفردية القصيرة.',
  ),
];
