import 'package:get/get.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/auth_session_service.dart';

import '../favourites/controllers/favourites_controller.dart';
import '../favourites/repositories/favourites_repository.dart';
import '../history/controllers/history_controller.dart';
import '../history/repositories/history_repository.dart';
import '../offers/controllers/offers_controller.dart';
import '../offers/repositories/offers_repository.dart';
import '../settings/controllers/settings_controller.dart';
import '../support/controllers/complaint_controller.dart';
import '../support/controllers/referral_controller.dart';
import '../support/repositories/support_repository.dart';
import '../wallet/controllers/wallet_controller.dart';
import '../wallet/repositories/wallet_repository.dart';

class AccountBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<FavouritesRepository>())
      Get.lazyPut<FavouritesRepository>(
          () => ApiFavouritesRepository(
              Get.find<ApiClient>(), Get.find<AuthSessionService>()),
          fenix: true);
    if (!Get.isRegistered<WalletRepository>())
      Get.lazyPut<WalletRepository>(
          () => ApiWalletRepository(
              Get.find<ApiClient>(), Get.find<AuthSessionService>()),
          fenix: true);
    if (!Get.isRegistered<OffersRepository>())
      Get.lazyPut<OffersRepository>(
          () => ApiOffersRepository(Get.find<ApiClient>()),
          fenix: true);
    if (!Get.isRegistered<HistoryRepository>())
      Get.lazyPut<HistoryRepository>(
          () => ApiHistoryRepository(
              Get.find<ApiClient>(), Get.find<AuthSessionService>()),
          fenix: true);
    if (!Get.isRegistered<ComplaintRepository>())
      Get.lazyPut<ComplaintRepository>(
          () => ApiComplaintRepository(Get.find<ApiClient>()),
          fenix: true);
    if (!Get.isRegistered<ReferralRepository>())
      Get.lazyPut<ReferralRepository>(
          () => ApiReferralRepository(Get.find<ApiClient>()),
          fenix: true);
    if (!Get.isRegistered<FavouritesController>()) {
      Get.lazyPut<FavouritesController>(
        () => FavouritesController(Get.find<FavouritesRepository>()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<WalletController>()) {
      Get.lazyPut<WalletController>(
        () => WalletController(Get.find<WalletRepository>()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<OffersController>()) {
      Get.lazyPut<OffersController>(
        () => OffersController(Get.find<OffersRepository>()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<HistoryController>()) {
      Get.lazyPut<HistoryController>(
        () => HistoryController(Get.find<HistoryRepository>()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<ComplaintController>()) {
      Get.lazyPut<ComplaintController>(
        () => ComplaintController(Get.find<ComplaintRepository>()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<ReferralController>()) {
      Get.lazyPut<ReferralController>(
        () => ReferralController(Get.find<ReferralRepository>()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<SettingsController>()) {
      Get.lazyPut<SettingsController>(
        SettingsController.new,
        fenix: true,
      );
    }
  }
}
