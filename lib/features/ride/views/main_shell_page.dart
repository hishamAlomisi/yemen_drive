import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../account/favourites/views/favourites_view.dart';
import '../../account/offers/views/offers_view.dart';
import '../../account/profile/views/profile_view.dart';
import '../../account/wallet/views/wallet_view.dart';
import '../controllers/ride_controller.dart';
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
            body: switch (controller.bottomNavigationIndex.value) {
              0 => const LocationPickerPage(isMainShell: true),
              1 => const FavouritesPage(embedded: true),
              2 => const WalletPage(embedded: true),
              3 => const OffersPage(embedded: true),
              _ => const ProfilePage(embedded: true),
            },
          ),
        ),
      );
}
