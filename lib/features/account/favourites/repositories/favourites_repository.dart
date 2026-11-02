import '../models/saved_place_labels.dart';

import '../../models/account_models.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';

abstract interface class FavouritesRepository {
  Future<List<FavouritePlace>> list();
  Future<void> add(
      {required String label,
      required String address,
      required double latitude,
      required double longitude,
      String kind = 'place'});
  Future<void> remove(String id);
}

class ApiFavouritesRepository implements FavouritesRepository {
  const ApiFavouritesRepository(this._client, this._session);
  final ApiClient _client;
  final AuthSessionService _session;
  @override
  Future<List<FavouritePlace>> list() async {
    if (!_session.isAuthenticated.value) return const [];
    final result = await _client.execute<Object?>(
        model: 'SavedPlaceModel', operation: 'list', data: const {});
    if (result is! ApiSuccess || result.data is! List)
      throw Exception('تعذر تحميل المفضلة. أعد المحاولة.');
    return (result.data as List)
        .whereType<Map<String, dynamic>>()
        .map((item) => FavouritePlace(
              id: '${item['id'] ?? ''}',
              title: '${item['label'] ?? item['title'] ?? 'مكان محفوظ'}',
              address: '${item['address'] ?? ''}',
              icon: savedPlaceIcon('${item['kind'] ?? 'place'}'),
              kind: '${item['kind'] ?? 'place'}',
              latitude: (item['latitude'] as num?)?.toDouble(),
              longitude: (item['longitude'] as num?)?.toDouble(),
            ))
        .toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    if (!_session.isAuthenticated.value)
      throw Exception('سجل الدخول لإدارة المفضلة.');
    final result = await _client.execute<Object?>(
        model: 'SavedPlaceModel',
        operation: 'delete',
        data: {'id': int.tryParse(id)});
    if (result is! ApiSuccess) throw Exception('تعذر حذف المكان.');
  }

  @override
  Future<void> add(
      {required String label,
      required String address,
      required double latitude,
      required double longitude,
      String kind = 'place'}) async {
    if (!_session.isAuthenticated.value)
      throw Exception('سجل الدخول لحفظ المفضلة.');
    final result = await _client
        .execute<Object?>(model: 'SavedPlaceModel', operation: 'add', data: {
      'label': label,
      'kind': kind,
      'address': address,
      'latitude': latitude,
      'longitude': longitude
    });
    if (result is! ApiSuccess)
      throw Exception(result is ApiFailure
          ? result.problem.detail ?? result.problem.title
          : 'تعذر حفظ المكان.');
  }
}
