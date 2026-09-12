import 'package:get/get.dart';
import '../../models/account_models.dart';
import '../repositories/history_repository.dart';

class HistoryController extends GetxController {
  HistoryController(this._repository);

  final HistoryRepository _repository;
  final RxList<RideHistoryItem> rides = <RideHistoryItem>[].obs;
  final RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      rides.assignAll(await _repository.list());
    } finally {
      isLoading.value = false;
    }
  }

  List<RideHistoryItem> byStatus(RideHistoryStatus status) =>
      rides.where((ride) => ride.status == status).toList(growable: false);
}
