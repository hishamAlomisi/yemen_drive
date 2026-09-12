import 'package:get/get.dart';
import '../../models/account_models.dart';
import '../repositories/offers_repository.dart';

class OffersController extends GetxController {
  OffersController(this._repository);

  final OffersRepository _repository;
  final RxList<RideOffer> offers = <RideOffer>[].obs;
  final RxBool isLoading = true.obs;
  final RxString selectedOfferId = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      offers.assignAll(await _repository.list());
    } finally {
      isLoading.value = false;
    }
  }

  void select(RideOffer offer) => selectedOfferId.value = offer.id;

  RideOffer? get selectedOffer {
    final routeId = Get.parameters['id'];
    final id = routeId?.isNotEmpty == true ? routeId! : selectedOfferId.value;
    for (final offer in offers) {
      if (offer.id == id) return offer;
    }
    return offers.isEmpty ? null : offers.first;
  }
}
