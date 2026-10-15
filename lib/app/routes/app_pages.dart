import 'package:get/get.dart';

import '../../features/account/account_routes.dart';
import '../../features/auth/routes/auth_routes.dart';
import '../../features/ride/ride_routes.dart';

abstract final class AppPages {
  static List<GetPage<dynamic>> get pages => appPages;
}

List<GetPage<dynamic>> get appPages => <GetPage<dynamic>>[
      ...authPages,
      ...ridePages,
      ...accountPages,
    ];
