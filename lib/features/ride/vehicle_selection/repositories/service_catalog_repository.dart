import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../shared/models/ride_models.dart';
import '../../models/ride_models.dart';

abstract interface class ServiceCatalogRepository {
  Future<List<RideVehicle>> getServices({
    required int serviceKindId,
  });
}

class ApiServiceCatalogRepository implements ServiceCatalogRepository {
  const ApiServiceCatalogRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<RideVehicle>> getServices({
    required int serviceKindId,
  }) async {
    final result = await _client.execute<Object?>(
      model: 'ServiceCatalogModel',
      operation: 'list',
      data: <String, Object?>{'serviceKindId': serviceKindId},
    );
    if (result is! ApiSuccess) return const <RideVehicle>[];
    final rawItems = result.data;
    if (rawItems is! List) return const <RideVehicle>[];

    return rawItems
        .whereType<Map<Object?, Object?>>()
        .where((item) => item['isActive'] != false)
        .map(
          (item) => RideVehicleOption.fromJson(Map<String, Object?>.from(item)),
        )
        .map(_toRideVehicle)
        .whereType<RideVehicle>()
        .toList(growable: false);
  }

  RideVehicle? _toRideVehicle(RideVehicleOption option) {
    final type = _vehicleType(option.category);
    if (option.id.trim().isEmpty || option.serviceKindId == null) return null;
    final imageUrl = option.imageUrl?.trim();
    return RideVehicle(
      id: option.id,
      name: option.name,
      type: type ?? RideVehicleType.car,
      serviceKindId: option.serviceKindId,
      serviceCatalogItemId: option.serviceCatalogItemId,
      category: option.category,
      arrivalMinutes: option.etaMinutes,
      price: option.price,
      rating: option.rating,
      seats: option.seats,
      description: option.description,
      imageAsset: imageUrl == null || imageUrl.isEmpty ? null : imageUrl,
      isRecommended: option.isRecommended,
    );
  }

  RideVehicleType? _vehicleType(String value) {
    final normalized = value.trim().toLowerCase();
    for (final type in RideVehicleType.values) {
      if (type.name == normalized) return type;
    }
    return null;
  }
}
