import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/auth_session_service.dart';
import '../controllers/chat_controller.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../controllers/notifications_controller.dart';
import '../controllers/payment_controller.dart';
import '../controllers/ride_controller.dart';
import '../controllers/safety_recording_controller.dart';
import '../home/repositories/service_kind_repository.dart';
import '../location_selection/repositories/location_search_repository.dart';
import '../location_selection/repositories/route_repository.dart';
import '../negotiation/repositories/ride_negotiation_repository.dart';
import '../vehicle_selection/repositories/service_catalog_repository.dart';

class RideBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<RideNegotiationRepository>()) {
      Get.put<RideNegotiationRepository>(
        ApiRideNegotiationRepository(Get.find<ApiClient>()),
        permanent: true,
      );
    }
    if (!Get.isRegistered<RideController>()) {
      if (!Get.isRegistered<ServiceCatalogRepository>() &&
          Get.isRegistered<ApiClient>()) {
        Get.put<ServiceCatalogRepository>(
          ApiServiceCatalogRepository(Get.find<ApiClient>()),
          permanent: true,
        );
      }
      if (!Get.isRegistered<ServiceKindRepository>() &&
          Get.isRegistered<ApiClient>())
        Get.put<ServiceKindRepository>(
            ApiServiceKindRepository(Get.find<ApiClient>()),
            permanent: true);
      Get.put<RideController>(
        RideController(
          Get.find<RideNegotiationRepository>(),
          Get.find<AuthSessionService>(),
          Get.isRegistered<ServiceCatalogRepository>()
              ? Get.find<ServiceCatalogRepository>()
              : null,
          Get.isRegistered<ServiceKindRepository>()
              ? Get.find<ServiceKindRepository>()
              : null,
        ),
        permanent: true,
      );
    }
    if (!Get.isRegistered<LocationController>()) {
      if (!Get.isRegistered<RouteRepository>()) {
        Get.put<RouteRepository>(GoogleRoutesRepository(), permanent: true);
      }
      if (!Get.isRegistered<LocationSearchRepository>()) {
        Get.put<LocationSearchRepository>(
          GoogleLocationSearchRepository(),
          permanent: true,
        );
      }
      Get.put<LocationController>(
        LocationController(
          Get.find<RouteRepository>(),
          Get.find<LocationSearchRepository>(),
          Get.find<ApiClient>(),
        ),
        permanent: true,
      );
    }
    Get.lazyPut<NotificationsController>(
      () => NotificationsController(
        Get.find<ApiClient>(),
        Get.find<AuthSessionService>(),
      ),
      fenix: true,
    );
    Get.lazyPut<ChatController>(
      () => ChatController(
        Get.find<ApiClient>(),
        Get.find<AuthSessionService>(),
        Get.find<RideController>(),
      ),
      fenix: true,
    );
    Get.lazyPut<PaymentController>(PaymentController.new, fenix: true);
    Get.lazyPut<SafetyRecordingController>(
      () => SafetyRecordingController(
        Get.find<ApiClient>(),
        Get.find<RideController>(),
      ),
      fenix: true,
    );
  }
}
