import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../account/favourites/views/favourites_view.dart';
import '../../account/offers/views/offers_view.dart';
import '../../account/profile/views/profile_view.dart';
import '../../account/wallet/views/wallet_view.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../widgets/ride_home_template.dart';
import 'home_notifications_location_views.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  late final RideController controller = Get.find<RideController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final arguments = Get.arguments;
      final rawPayload =
          arguments is Map ? arguments['pushNotification'] : null;
      if (!mounted || rawPayload is! Map) return;
      final payload =
          rawPayload.map((key, value) => MapEntry('$key', '$value'));
      controller.openNotificationPayload(payload);
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: Directionality.of(context),
        child: Obx(
          () => Scaffold(
            body: IndexedStack(
              index: controller.bottomNavigationIndex.value,
              children: <Widget>[
                Obx(
                  () => controller.autoStartTransport.value
                      ? const LocationPickerPage(isMainShell: true)
                      : RideHomeTemplate(
                          type: controller.serviceType.value,
                          showBottomNavigation: false,
                          embedded: true,
                        ),
                ),
                controller.autoStartTransport.value
                    ? RideHomeTemplate(
                        type: RideServiceType.transport,
                        showBottomNavigation: false,
                        embedded: true,
                      )
                    : const FavouritesPage(embedded: true),
                const WalletPage(embedded: true),
                const OffersPage(embedded: true),
                const ProfilePage(embedded: true),
              ],
            ),
            bottomNavigationBar: AppBottomNav(
              currentIndex: controller.bottomNavigationIndex.value,
              onTap: controller.updateBottomNavigation,
              showServices: controller.autoStartTransport.value,
            ),
          ),
        ),
      );
}
