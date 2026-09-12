import '../../models/account_models.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

abstract interface class OffersRepository {
  Future<List<RideOffer>> list();
}

class ApiOffersRepository implements OffersRepository {
  const ApiOffersRepository(this._client);
  final ApiClient _client;
  @override
  Future<List<RideOffer>> list() async {
    final result = await _client.execute<Object?>(
        model: 'PromotionModel', operation: 'list');
    if (result is! ApiSuccess || result.data is! List) return const [];
    return (result.data as List)
        .whereType<Map>()
        .map((item) => RideOffer(
              id: '${item['id'] ?? ''}',
              title: '${item['title'] ?? item['name'] ?? 'عرض تجريبي'}',
              discount: '${item['discount'] ?? ''}',
              code: '${item['code'] ?? ''}',
              description: '${item['description'] ?? ''}',
              expiryLabel: '${item['expiresAtUtc'] ?? ''}',
            ))
        .toList(growable: false);
  }
}
