import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_google_map.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/directional_arrow.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../controllers/notifications_controller.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../widgets/ride_common_widgets.dart';
import '../widgets/ride_home_template.dart';
import '../widgets/ride_location_widgets.dart';
import '../widgets/ride_map_shell.dart';
import '../booking/widgets/booking_panel.dart';
import '../booking/controllers/booking_controller.dart';
import '../widgets/ride_vehicle_widgets.dart';

class HomeTransportPage extends StatelessWidget {
  const HomeTransportPage({super.key});

  @override
  Widget build(BuildContext context) => const LocationPickerPage();
}

class HomeDeliveryPage extends StatelessWidget {
  const HomeDeliveryPage({super.key});

  @override
  Widget build(BuildContext context) => const LocationPickerPage();
}

class NotificationsPage extends GetView<NotificationsController> {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        title: 'الإشعارات',
        actions: <Widget>[
          TextButton(
            onPressed: controller.markAllRead,
            child: const Text('قراءة الكل'),
          ),
        ],
        body: Obx(
          () => controller.items.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none, size: 48),
                  SizedBox(height: 16),
                  Text('لا توجد إشعارات حالياً'),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  itemCount: controller.items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = controller.items[index];
                    return _NotificationTile(
                        item: item, onTap: () => controller.markRead(item));
                  },
                ),
        ),
      );
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({this.isMainShell = false, super.key});

  final bool isMainShell;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final LocationController controller = Get.find<LocationController>();
  final RideController rideController = Get.find<RideController>();
  final BookingController booking = Get.find<BookingController>();
  final DraggableScrollableController _sheet = DraggableScrollableController();
  final ValueNotifier<double> _extent = ValueNotifier<double>(.64);
  Worker? _bookingWorker;
  Worker? _mapSelectionWorker;
  Timer? _focusTimer;
  int _focusRevision = 0;
  bool _previewingRoute = false;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_sheetChanged);
    _mapSelectionWorker = ever(controller.isChoosingMapPoint, (bool choosing) {
      if (choosing) unawaited(_animateSheet(.12));
    });
    _bookingWorker = ever(booking.isOpeningHomeBooking, (bool opening) {
      if (!opening && _previewingRoute && mounted) {
        _previewingRoute = false;
        unawaited(_animateSheet(.64));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        if (!mounted) return;
        rideController.applyAdminDefaultServiceKind();
        await controller.ensureInitialPickupLocation();
        if (!mounted) return;
        if (rideController.nearbyDrivers.isEmpty) {
          await rideController.loadNearbyDrivers(
              center: controller.pickup.value);
        }
      },
    );
  }

  void _sheetChanged() {
    if (!_sheet.isAttached) return;
    _extent.value = _sheet.size;
    _focusTimer?.cancel();
    if (controller.hasDrivingRoute) {
      _focusTimer = Timer(const Duration(milliseconds: 220), () {
        if (mounted) setState(() => _focusRevision++);
      });
    }
  }

  Future<void> _animateSheet(double size) async {
    if (!mounted || !_sheet.isAttached) return;
    await _sheet.animateTo(size,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic);
  }

  Future<void> _previewRoute() async {
    _previewingRoute = true;
    await _animateSheet(.12);
    if (!mounted) return;
    _focusTimer?.cancel();
    setState(() => _focusRevision++);
    // Let the passenger see the complete road route before fare review opens.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = LayoutBuilder(
        builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _extent,
                  builder: (context, extent, _) => Obx(() => NearbyDriversMap(
                        initialTarget: controller.pickup.value ??
                            const LatLng(15.3694, 44.1910),
                        mapType: controller.mapType.value,
                        followTarget: controller.pickup.value,
                        additionalMarkers: controller.markers,
                        polylines: controller.polylines,
                        focusBounds: controller.hasDrivingRoute
                            ? controller.selectedRouteBounds
                            : null,
                        focusBoundsRevision: _focusRevision,
                        onMapCreated: controller.onMapCreated,
                        onTap: controller.isChoosingMapPoint.value
                            ? controller.selectMapPoint
                            : null,
                        minimumCardTop: 90,
                        useModernMapStyle: true,
                        mapPadding: EdgeInsets.only(
                          top: MediaQuery.paddingOf(context).top + 78,
                          bottom: (constraints.maxHeight * extent + 8)
                              .clamp(
                                  0.0,
                                  (constraints.maxHeight -
                                          MediaQuery.paddingOf(context).top -
                                          200)
                                      .clamp(0.0, double.infinity))
                              .toDouble(),
                        ),
                      )),
                ),
                Positioned(
                  top: 0,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Obx(() => controller.isChoosingMapPoint.value
                            ? Material(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(16),
                                child: Row(children: [
                                  IconButton(
                                      onPressed: controller.cancelMapSelection,
                                      icon: const Icon(Icons.close_rounded)),
                                  Expanded(
                                      child: Text('home_choose_map_point'.tr)),
                                ]))
                            : widget.isMainShell
                                ? const RideHomeHeader(routePicker: true)
                                : const Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: RideBackButton())),
                      )),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _extent,
                  builder: (context, extent, _) => Positioned(
                    left: 16,
                    right: 16,
                    bottom: constraints.maxHeight * extent + 12,
                    child: Visibility(
                      visible: constraints.maxHeight * (1 - extent) > 170,
                      child: Row(textDirection: TextDirection.ltr, children: [
                        RideIconButton(
                          icon: Icons.near_me_outlined,
                          tooltip: 'use_my_location'.tr,
                          onPressed: () {
                            if (booking.isOpeningHomeBooking.value ||
                                rideController.bookingLocked) return;
                            if (controller.hasDrivingRoute) {
                              setState(() => _focusRevision++);
                            } else {
                              unawaited(controller.useCurrentLocation());
                            }
                          },
                        ),
                        const Spacer(),
                        Obx(() => IconButton.filled(
                              key: const ValueKey('home-continue-icon'),
                              tooltip: 'home_continue'.tr,
                              style: IconButton.styleFrom(
                                backgroundColor: colors.surface,
                                foregroundColor: colors.onSurface,
                              ),
                              onPressed: booking.isOpeningHomeBooking.value ||
                                      rideController.bookingLocked
                                  ? null
                                  : () => booking.continueFromHome(
                                      previewRoute: _previewRoute),
                              icon: const BackButtonIcon(),
                            )),
                      ]),
                    ),
                  ),
                ),
                DraggableScrollableSheet(
                  key: const ValueKey('home-services-sheet'),
                  controller: _sheet,
                  initialChildSize: .64,
                  minChildSize: .12,
                  maxChildSize: .90,
                  snap: true,
                  snapSizes: const [.12, .64, .90],
                  builder: (context, scrollController) => Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Material(
                        color: colors.surfaceContainerLow,
                        elevation: 0,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28)),
                        clipBehavior: Clip.antiAlias,
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.fromLTRB(8, 0, 8,
                              MediaQuery.paddingOf(context).bottom + 12),
                          children: [
                            Semantics(
                              button: true,
                              label: 'home_expand'.tr,
                              child: InkWell(
                                key: const ValueKey('home-sheet-handle'),
                                onTap: () => _animateSheet(
                                    _sheet.size > .70 ? .64 : .90),
                                child: Center(
                                    child: Container(
                                  width: 42,
                                  height: 5,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                      color: colors.outlineVariant,
                                      borderRadius: BorderRadius.circular(5)),
                                )),
                              ),
                            ),
                            BookingPanel(previewRoute: _previewRoute),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ));
    return widget.isMainShell ? content : Scaffold(body: content);
  }

  @override
  void dispose() {
    _bookingWorker?.dispose();
    _mapSelectionWorker?.dispose();
    _focusTimer?.cancel();
    _sheet.removeListener(_sheetChanged);
    _sheet.dispose();
    _extent.dispose();
    super.dispose();
  }
}

class LocationAddressPage extends GetView<LocationController> {
  const LocationAddressPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        title: 'بيانات عنوان الوجهة',
        resizeToAvoidBottomInset: true,
        footer: AppButton(
          label: 'الانتقال إلى تأكيد الوجهة',
          leading: const DirectionalArrowIcon(forward: true),
          onPressed: controller.openLocationConfirmation,
        ),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const RideSectionHeader(
                title: 'تفاصيل العنوان',
                subtitle: 'أضف اسمًا واضحًا للوجهة ليسهل الوصول إليها.',
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.location_on_rounded,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'الوجهة المختارة',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.toController.text.trim().isEmpty
                                ? 'لم يتم إدخال اسم للوجهة'
                                : controller.toController.text,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: controller.addressNameController,
                label: 'اسم العنوان *',
                hint: 'مثال: المنزل، العمل، مستشفى الثورة',
                prefixIcon: Icon(Icons.bookmark_outline_rounded),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: controller.streetController,
                label: 'اسم الشارع',
                hint: 'يُعبأ تلقائيًا عند توفره',
                prefixIcon: Icon(Icons.add_road_rounded),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: controller.detailsController,
                label: 'تفاصيل العنوان',
                hint: 'الحي، المبنى، علامة مميزة',
                prefixIcon: Icon(Icons.notes_rounded),
                maxLines: 3,
              ),
              if (controller.isAddressLoading.value)
                Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      );
}

class LocationSearchPage extends StatelessWidget {
  const LocationSearchPage({super.key});

  @override
  Widget build(BuildContext context) => const RidePageFrame(
        title: 'أدخل مسارك',
        resizeToAvoidBottomInset: true,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: LocationSearchForm(),
        ),
      );
}

class LocationConfirmPage extends GetView<LocationController> {
  const LocationConfirmPage({super.key});

  @override
  Widget build(BuildContext context) {
    final rideController = Get.find<RideController>();
    return RideMapShell(
      processStep: 2,
      showRoute: true,
      map: Obx(
        () => AppGoogleMap(
          markers: controller.markers,
          polylines: controller.polylines,
          mapType: controller.mapType.value,
          useModernMapStyle: true,
          focusBounds: controller.selectedRouteBounds,
          focusBoundsPadding: 104,
          onMapCreated: (mapController) {
            controller.onMapCreated(mapController);
            controller.focusRoute();
          },
          myLocationEnabled: false,
        ),
      ),
      panelMaxHeightFactor: .72,
      fitPanelToContent: true,
      panelFooter: Obx(
        () => AppButton(
          label: 'continue_to_negotiation'.tr,
          leading: const DirectionalArrowIcon(forward: true),
          isDisabled: !rideController.hasSelectedTransport.value,
          isLoading: rideController.negotiationStatus.value ==
              NegotiationStatus.quoting,
          onPressed: () {
            if (!controller.confirmLocation()) return;
            rideController.selectTransport(
              rideController.selectedTransport.value,
            );
          },
        ),
      ),
      top: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          const RideBackButton(),
          RideIconButton(
            icon: Icons.gps_fixed_rounded,
            tooltip: 'إعادة تمركز الخريطة',
            onPressed: controller.focusRoute,
          ),
        ],
      ),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RidePanelHandle(),
          RideSectionHeader(
            title: 'confirm_destination'.tr,
            subtitle: 'confirm_destination_hint'.tr,
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.location_on_rounded,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    controller.addressNameController.text.trim().isEmpty
                        ? controller.confirmedDestination.value
                        : '${controller.addressNameController.text}\n${controller.streetController.text}',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: Get.back<void>,
                  tooltip: 'تعديل بيانات العنوان',
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          RideSectionHeader(
            title: 'how_to_arrive'.tr,
            subtitle: 'choose_transport_hint'.tr,
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () {
              if (rideController.isCatalogLoading.value &&
                  rideController.vehicles.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final vehicles = rideController.vehicles;
              if (vehicles.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    rideController.catalogError.value.isEmpty
                        ? 'لا توجد وسائل متاحة لهذا النوع حاليًا.'
                        : rideController.catalogError.value,
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return Column(
                children: vehicles
                    .map(
                      (vehicle) => CatalogTransportListCard(
                        vehicle: vehicle,
                        selected: rideController.selectedVehicle.value?.id ==
                            vehicle.id,
                        onTap: () =>
                            rideController.chooseCatalogVehicle(vehicle),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final RideNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      'offer' => Icons.local_offer_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      _ => Icons.local_taxi_outlined,
    };
    return AppCard(
      onTap: onTap,
      color: item.isRead
          ? null
          : AppColors.primary.withValues(
              alpha:
                  Theme.of(context).brightness == Brightness.dark ? .09 : .12,
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryDark),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!item.isRead)
                      Padding(
                        padding: EdgeInsetsDirectional.only(start: 8),
                        child: CircleAvatar(
                          radius: 4,
                          backgroundColor: AppColors.secondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.body, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  item.timeLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
