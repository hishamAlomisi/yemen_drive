import 'package:get/get.dart';

import '../account/bindings/account_binding.dart';
import '../account/profile/bindings/profile_binding.dart';
import 'bindings/ride_binding.dart';
import 'home/views.dart';
import 'location_selection/bindings/location_selection_binding.dart';
import 'negotiation/bindings/negotiation_binding.dart';
import 'negotiation/views.dart';
import 'trip/views.dart';
import 'vehicle_selection/views.dart';

abstract final class RideRoutes {
  static const String homeTransport = '/home';
  static const String homeDelivery = '/home/delivery';
  static const String notifications = '/notifications';
  static const String locationPicker = '/ride/location';
  static const String locationSearch = '/ride/location/search';
  static const String locationAddress = '/ride/location/address';
  static const String locationConfirm = '/ride/location/confirm';
  static const String transportSelection = '/ride/transport';
  static const String vehicleCatalog = '/ride/vehicles';
  static const String vehicleList = '/ride/vehicles/list';
  static const String vehicleDetails = '/ride/vehicles/details';
  static const String rideRequest = '/ride/request';
  static const String negotiationQuote = '/ride/negotiation/quote';
  static const String rideCancel = '/ride/request/cancel';
  static const String requestThanks = '/ride/request/thanks';
  static const String driverLocation = '/ride/driver-location';
  static const String chat = '/ride/chat';
  static const String call = '/ride/call';
  static const String activeCall = '/ride/call/active';
  static const String payment = '/ride/payment';
  static const String activeRide = '/ride/active';
  static const String review = '/ride/review';
  static const String rideThanks = '/ride/thanks';
}

List<GetPage<dynamic>> get ridePages => <GetPage<dynamic>>[
      GetPage<dynamic>(
        name: RideRoutes.homeTransport,
        page: MainShellPage.new,
        bindings: <Bindings>[
          RideBinding(),
          AccountBinding(),
          ProfileBinding(),
        ],
        transition: Transition.noTransition,
      ),
      GetPage<dynamic>(
        name: RideRoutes.homeDelivery,
        page: MainShellPage.new,
        bindings: <Bindings>[
          RideBinding(),
          AccountBinding(),
          ProfileBinding(),
        ],
        transition: Transition.noTransition,
      ),
      _ridePage(RideRoutes.notifications, NotificationsPage.new),
      _ridePage(RideRoutes.locationPicker, LocationPickerPage.new,
          binding: LocationSelectionBinding()),
      _ridePage(RideRoutes.locationSearch, LocationSearchPage.new,
          binding: LocationSelectionBinding()),
      _ridePage(RideRoutes.locationAddress, LocationAddressPage.new,
          binding: LocationSelectionBinding()),
      _ridePage(RideRoutes.locationConfirm, LocationConfirmPage.new,
          binding: LocationSelectionBinding()),
      _ridePage(RideRoutes.transportSelection, TransportSelectionPage.new),
      _ridePage(RideRoutes.vehicleCatalog, VehicleCatalogPage.new),
      _ridePage(RideRoutes.vehicleList, VehicleListPage.new),
      _ridePage(RideRoutes.vehicleDetails, VehicleDetailsPage.new),
      _ridePage(RideRoutes.rideRequest, RideRequestPage.new),
      _ridePage(RideRoutes.negotiationQuote, NegotiationQuotePage.new,
          binding: NegotiationBinding()),
      _ridePage(RideRoutes.rideCancel, RideCancelPage.new),
      _ridePage(RideRoutes.requestThanks, RequestThanksPage.new),
      _ridePage(RideRoutes.driverLocation, DriverLocationPage.new),
      _ridePage(RideRoutes.chat, RideChatPage.new),
      _ridePage(RideRoutes.call, DriverCallPage.new),
      _ridePage(RideRoutes.activeCall, ActiveCallPage.new),
      _ridePage(RideRoutes.payment, RidePaymentPage.new),
      _ridePage(RideRoutes.activeRide, ActiveRidePage.new),
      _ridePage(RideRoutes.review, RideReviewPage.new),
      _ridePage(RideRoutes.rideThanks, RideThanksPage.new),
    ];

GetPage<dynamic> _ridePage(String name, GetPageBuilder page,
        {Bindings? binding}) =>
    GetPage<dynamic>(
      name: name,
      page: page,
      binding: binding ?? RideBinding(),
      transition: Transition.cupertino,
    );
