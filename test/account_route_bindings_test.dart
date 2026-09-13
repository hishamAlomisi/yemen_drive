import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/features/account/account_routes.dart';
import 'package:yemen_drive/features/account/bindings/account_binding.dart';
import 'package:yemen_drive/features/account/profile/bindings/profile_binding.dart';
import 'package:yemen_drive/features/ride/ride_routes.dart';

void main() {
  test('each account route declares the binding that owns its controller', () {
    final profilePage = accountPages.singleWhere(
      (page) => page.name == AccountRoutes.profile,
    );
    final offersPage = accountPages.singleWhere(
      (page) => page.name == AccountRoutes.offers,
    );

    expect(profilePage.binding, isA<ProfileBinding>());
    expect(offersPage.binding, isA<AccountBinding>());

    final homePage = ridePages.singleWhere(
      (page) => page.name == RideRoutes.homeTransport,
    );
    expect(homePage.bindings, contains(isA<ProfileBinding>()));
  });
}
