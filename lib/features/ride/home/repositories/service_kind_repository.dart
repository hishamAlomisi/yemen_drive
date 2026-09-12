import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../models/service_kind_models.dart';

abstract interface class ServiceKindRepository {
  Future<List<RideHomeService>> getServices();
}

class ApiServiceKindRepository implements ServiceKindRepository {
  const ApiServiceKindRepository(this.client);
  final ApiClient client;
  @override
  Future<List<RideHomeService>> getServices() async {
    final result = await client.execute<Object?>(
      model: 'ServiceKindModel',
      operation: 'list',
      data: {},
    );
    if (result is! ApiSuccess || result.data is! List) return const [];
    return (result.data as List)
        .whereType<Map<Object?, Object?>>()
        .where((raw) => raw['isActive'] != false)
        .map((raw) {
          final x = Map<String, Object?>.from(raw);
          return RideHomeService(
            id: (x['id'] as num?)?.toInt() ?? int.tryParse('${x['id'] ?? ''}'),
            code: '${x['code'] ?? ''}',
            name: '${x['name'] ?? x['nameAr'] ?? ''}',
            imageUrl: x['imageUrl']?.toString(),
            rideServiceType: x['rideServiceType']?.toString(),
            sortOrder: (x['sortOrder'] as num?)?.toInt() ?? 0,
          );
        })
        .where((x) => x.id != null && x.code.isNotEmpty)
        .toList(growable: false);
  }
}
