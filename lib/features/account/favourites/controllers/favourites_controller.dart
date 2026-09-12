import 'package:get/get.dart';
import '../../models/account_models.dart';
import '../repositories/favourites_repository.dart';

class FavouritesController extends GetxController {
  FavouritesController(this._repository);

  final FavouritesRepository _repository;
  final RxList<FavouritePlace> places = <FavouritePlace>[].obs;
  final RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      places.assignAll(await _repository.list());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> remove(FavouritePlace place) async {
    final oldIndex = places.indexOf(place);
    places.remove(place);
    try {
      await _repository.remove(place.id);
    } catch (_) {
      places.insert(oldIndex < 0 ? 0 : oldIndex, place);
      rethrow;
    }
  }

  Future<bool> add(
      {required String label,
      required String address,
      required double latitude,
      required double longitude,
      String kind = 'place'}) async {
    try {
      await _repository.add(
          label: label,
          address: address,
          latitude: latitude,
          longitude: longitude,
          kind: kind);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }
}
