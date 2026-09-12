import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

class ConnectivityService extends GetxService {
  final RxBool isOnline = true.obs;

  Future<ConnectivityService> init() async {
    await refresh();
    Connectivity().onConnectivityChanged.listen((_) => refresh());
    return this;
  }

  Future<bool> refresh() async {
    final results = await Connectivity().checkConnectivity();
    isOnline.value = results.any((item) => item != ConnectivityResult.none);
    return isOnline.value;
  }
}
