import 'dart:async';

import 'package:get/get.dart';

import '../../controllers/ride_controller.dart';
import '../../location_selection/controllers/location_selection_controller.dart';
import '../../models/ride_models.dart';
import '../../models/service_kind_models.dart';
import '../../ride_routes.dart';

/// Coordinates booking and fare review with the existing pricing/ride APIs.
class BookingController extends GetxController {
  BookingController(this.ride, this.location);

  final RideController ride;
  final LocationController location;
  final RxString quotedSelection = ''.obs;
  final RxBool isOpeningHomeBooking = false.obs;
  final RxMap<String, RideQuote> reviewQuotes = <String, RideQuote>{}.obs;
  final RxSet<String> loadingReviewQuotes = <String>{}.obs;
  final RxSet<String> failedReviewQuotes = <String>{}.obs;
  bool _reviewVisible = false;
  String _reviewPricesScope = '';
  int _reviewPricesRevision = 0;
  Worker? _selectionWorker;
  Timer? _quoteTimer;
  int _revision = 0;

  String get reviewPricesScope => <Object?>[
        location.pickup.value,
        location.destination.value,
        location.isRouteLoading.value,
        location.routeDistanceMeters.value,
        location.routeDurationSeconds.value,
        ride.selectedServiceKindId.value,
        ride.vehicles.map((vehicle) => vehicle.id).join(','),
      ].join('|');

  bool get canEnterReview =>
      !ride.bookingLocked &&
      !location.isRouteLoading.value &&
      location.canContinueLocationFlow &&
      location.serviceAreaAvailable.value != false &&
      ride.selectedServiceKindId.value != null &&
      ride.vehicles.isNotEmpty;

  String get selectionKey => <Object?>[
        location.pickup.value,
        location.destination.value,
        location.isRouteLoading.value,
        location.routeDistanceMeters.value,
        location.routeDurationSeconds.value,
        ride.selectedServiceKindId.value,
        ride.selectedVehicle.value?.serviceCatalogItemId,
      ].join('|');

  bool get canQuote =>
      !ride.bookingLocked &&
      !location.isRouteLoading.value &&
      location.canContinueLocationFlow &&
      location.serviceAreaAvailable.value != false &&
      ride.selectedVehicle.value?.serviceKindId ==
          ride.selectedServiceKindId.value &&
      ride.selectedVehicle.value?.serviceCatalogItemId != null;

  bool get canSubmit =>
      canQuote &&
      quotedSelection.value == selectionKey &&
      ride.quote.value != null &&
      ride.isPriceAllowed(ride.offeredPrice.value) &&
      ride.negotiationStatus.value == NegotiationStatus.ready;

  @override
  void onInit() {
    super.onInit();
    _selectionWorker = everAll(
      [
        location.pickup,
        location.destination,
        location.isRouteLoading,
        location.routeDistanceMeters,
        location.routeDurationSeconds,
        location.serviceAreaAvailable,
        ride.selectedServiceKindId,
        ride.selectedVehicle,
        ride.catalogVehicles,
      ],
      (_) => selectionChanged(),
    );
    selectionChanged();
  }

  void selectionChanged() {
    _quoteTimer?.cancel();
    if (ride.bookingLocked) return;
    _revision++;
    quotedSelection.value = '';
    ride.invalidateBookingQuote();
    final pricesScopeChanged = _reviewPricesScope != reviewPricesScope;
    if (pricesScopeChanged) {
      _reviewPricesRevision++;
      _reviewPricesScope = reviewPricesScope;
      reviewQuotes.clear();
      loadingReviewQuotes.clear();
      failedReviewQuotes.clear();
    }
    if (canQuote) {
      final cached = reviewQuotes[ride.selectedVehicle.value!.id];
      if (cached != null) {
        ride.applyBookingQuote(
          cached,
          distanceKm: location.routeDistanceMeters.value / 1000,
        );
        quotedSelection.value = selectionKey;
      } else {
        _quoteTimer = Timer(const Duration(milliseconds: 250), refreshQuote);
      }
    }
    if (pricesScopeChanged && _reviewVisible) unawaited(loadReviewQuotes());
  }

  Future<void> refreshQuote() async {
    _quoteTimer?.cancel();
    if (!canQuote) return;
    final key = selectionKey;
    final revision = ++_revision;
    await ride.refreshBookingQuote();
    if (revision == _revision &&
        key == selectionKey &&
        ride.quote.value != null) {
      quotedSelection.value = key;
      reviewQuotes[ride.selectedVehicle.value!.id] = ride.quote.value!;
    }
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    // A resolved address already satisfies RideModel; a separate naming screen
    // is optional and must not be a prerequisite for requesting a ride.
    location.confirmedDestination.value =
        location.addressNameController.text.trim().isNotEmpty
            ? location.addressNameController.text.trim()
            : location.toController.text.trim();
    await ride.requestRide(openSearchPage: true);
  }

  Future<void> openReview() async {
    if (!canEnterReview || Get.currentRoute == RideRoutes.negotiationQuote)
      return;
    await Get.toNamed<void>(RideRoutes.negotiationQuote);
    if (!isClosed && canQuote && ride.quote.value == null) {
      await refreshQuote();
    }
  }

  /// One home interaction keeps its service choice through the existing
  /// location search, route calculation and fare review. Cancelling search
  /// cancels this intent; passive GPS/catalog updates never navigate.
  Future<void> continueFromHome({
    int? editField,
    RideHomeService? service,
    RideVehicle? vehicle,
    Future<void> Function()? previewRoute,
  }) async {
    if (ride.bookingLocked || isOpeningHomeBooking.value || isClosed) return;
    final originRoute = Get.currentRoute;
    isOpeningHomeBooking.value = true;
    try {
      if (service != null) {
        final index =
            ride.homeServices.indexWhere((item) => item.id == service.id);
        if (index < 0) return;
        await ride.selectHomeService(index);
      }
      if (vehicle != null) {
        if (vehicle.serviceKindId != ride.selectedServiceKindId.value ||
            !ride.vehicles.any((item) => item.id == vehicle.id)) return;
        ride.chooseCatalogVehicle(vehicle);
      }
      if (isClosed || ride.bookingLocked) return;

      if (editField != null ||
          (!location.hasDrivingRoute && !location.isRouteLoading.value)) {
        var field = editField ?? (location.pickup.value == null ? 0 : 1);
        while (true) {
          final selected = await location.startSearch(field: field);
          if (!selected || isClosed || ride.bookingLocked) return;
          if (location.hasCompleteRoute) break;
          field = location.pickup.value == null ? 0 : 1;
        }
      }
      if (location.isRouteLoading.value) {
        await location.isRouteLoading.stream.firstWhere((loading) => !loading);
      }
      if (ride.isCatalogLoading.value) {
        await ride.isCatalogLoading.stream.firstWhere((loading) => !loading);
      }
      if (isClosed || !canEnterReview) return;

      final selection = selectionKey;
      final preview = previewRoute?.call();
      if (canQuote && !canSubmit) await refreshQuote();
      if (preview != null) await preview;
      if (isClosed ||
          Get.currentRoute != originRoute ||
          selection != selectionKey ||
          !canEnterReview) return;
      await openReview();
    } finally {
      if (!isClosed) isOpeningHomeBooking.value = false;
    }
  }

  void reviewOpened() {
    _reviewVisible = true;
    unawaited(loadReviewQuotes());
  }

  void reviewClosed() {
    _reviewVisible = false;
    _reviewPricesRevision++;
    loadingReviewQuotes.clear();
  }

  Future<void> chooseReviewVehicle(RideVehicle vehicle) async {
    if (ride.bookingLocked ||
        !ride.vehicles.any((item) => item.id == vehicle.id)) return;
    if (ride.selectedVehicle.value?.id == vehicle.id && canSubmit) return;
    ride.chooseCatalogVehicle(vehicle);
    if (loadingReviewQuotes.contains(vehicle.id)) {
      _quoteTimer?.cancel();
      final key = selectionKey;
      await loadingReviewQuotes.stream
          .firstWhere((ids) => !ids.contains(vehicle.id));
      if (isClosed || key != selectionKey || ride.bookingLocked) return;
      final cached = reviewQuotes[vehicle.id];
      if (cached != null) {
        ride.applyBookingQuote(
          cached,
          distanceKm: location.routeDistanceMeters.value / 1000,
        );
        quotedSelection.value = selectionKey;
      }
    }
    if (canQuote && !canSubmit) await refreshQuote();
  }

  Future<void> editReviewRoute(int field) async {
    if (ride.bookingLocked) return;
    await location.startSearch(field: field);
  }

  /// Preview each real service with the existing pricing operation. The scope
  /// excludes the selected vehicle, so switching rows reuses these prices.
  Future<void> loadReviewQuotes({bool retry = false}) async {
    if (!canEnterReview || isClosed) return;
    if (_reviewPricesScope != reviewPricesScope) {
      _reviewPricesRevision++;
      _reviewPricesScope = reviewPricesScope;
      reviewQuotes.clear();
      loadingReviewQuotes.clear();
      failedReviewQuotes.clear();
    }
    final revision = _reviewPricesRevision;
    final scope = _reviewPricesScope;
    final start = location.pickup.value!;
    final end = location.destination.value!;
    final distance = location.routeDistanceMeters.value / 1000;
    final duration = location.routeDurationSeconds.value / 60;
    if (canSubmit)
      reviewQuotes[ride.selectedVehicle.value!.id] = ride.quote.value!;
    final vehicles = ride.vehicles
        .where(
          (vehicle) =>
              vehicle.serviceCatalogItemId != null &&
              !(vehicle.id == ride.selectedVehicle.value?.id &&
                  ((_quoteTimer?.isActive ?? false) ||
                      ride.negotiationStatus.value ==
                          NegotiationStatus.quoting)) &&
              vehicle.serviceKindId == ride.selectedServiceKindId.value &&
              !reviewQuotes.containsKey(vehicle.id) &&
              !loadingReviewQuotes.contains(vehicle.id) &&
              (retry || !failedReviewQuotes.contains(vehicle.id)),
        )
        .toList(growable: false);
    loadingReviewQuotes.addAll(vehicles.map((vehicle) => vehicle.id));
    for (var offset = 0; offset < vehicles.length; offset += 3) {
      if (isClosed || revision != _reviewPricesRevision) return;
      await Future.wait(
        vehicles.skip(offset).take(3).map((vehicle) async {
          try {
            final value = await ride.fetchCatalogQuote(
              vehicle: vehicle,
              pickup: RideCoordinate(
                latitude: start.latitude,
                longitude: start.longitude,
              ),
              destination: RideCoordinate(
                latitude: end.latitude,
                longitude: end.longitude,
              ),
              distanceKm: distance,
              durationMinutes: duration,
            );
            if (isClosed ||
                revision != _reviewPricesRevision ||
                scope != reviewPricesScope) return;
            reviewQuotes[vehicle.id] = value;
            failedReviewQuotes.remove(vehicle.id);
          } catch (_) {
            if (!isClosed && revision == _reviewPricesRevision)
              failedReviewQuotes.add(vehicle.id);
          } finally {
            if (!isClosed && revision == _reviewPricesRevision)
              loadingReviewQuotes.remove(vehicle.id);
          }
        }),
      );
    }
  }

  @override
  void onClose() {
    _reviewPricesRevision++;
    _selectionWorker?.dispose();
    _quoteTimer?.cancel();
    super.onClose();
  }
}
