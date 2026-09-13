import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/config/app_environment.dart';
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
import '../widgets/ride_process_stepper.dart';
import '../widgets/ride_vehicle_widgets.dart';

class HomeTransportPage extends StatelessWidget {
  const HomeTransportPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const RideHomeTemplate(type: RideServiceType.transport);
}

class HomeDeliveryPage extends StatelessWidget {
  const HomeDeliveryPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const RideHomeTemplate(type: RideServiceType.delivery);
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
          () => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            itemCount: controller.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        if (!mounted) return;
        if (rideController.autoStartTransport.value) {
          rideController.applyAdminDefaultServiceKind();
        }
        await controller.ensureInitialPickupLocation();
        if (!mounted) return;
        if (rideController.nearbyDrivers.isEmpty) {
          if (AppEnvironment.useDemoData)
            rideController.loadDemoNearbyDrivers();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => RideMapShell(
        map: Obx(
          () => NearbyDriversMap(
            initialTarget:
                controller.pickup.value ?? const LatLng(15.3694, 44.1910),
            initialZoom: 13.5,
            followTarget: controller.pickup.value,
            additionalMarkers: controller.markers,
            polylines: controller.polylines,
            onMapCreated: controller.onMapCreated,
            onTap: controller.selectMapPoint,
            minimumCardTop: 230,
          ),
        ),
        showPanel: false,
        panel: const SizedBox.shrink(),
        embedded: widget.isMainShell,
        top: widget.isMainShell ? const RideHomeHeader() : null,
        overlay: _LocationPickerOverlay(
          controller: controller,
          showBackButton: !widget.isMainShell,
        ),
      );
}

class _LocationPickerOverlay extends StatefulWidget {
  const _LocationPickerOverlay({
    required this.controller,
    required this.showBackButton,
  });

  final LocationController controller;
  final bool showBackButton;

  @override
  State<_LocationPickerOverlay> createState() => _LocationPickerOverlayState();
}

class _LocationPickerOverlayState extends State<_LocationPickerOverlay> {
  bool _showSaved = false;

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          Positioned(
            top: MediaQuery.paddingOf(context).top +
                (widget.showBackButton ? 12 : 88),
            left: 16,
            right: 72,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xD92D355E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x667E89B8)),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: InteractiveRouteFieldsOverlay(),
                      ),
                    ),
                    const SizedBox(height: 7),
                    RideProcessStepper(
                      currentStep: 1,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.showBackButton)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              right: 16,
              child: RideIconButton(
                iconWidget: const DirectionalArrowIcon(forward: false),
                tooltip: 'عودة',
                onPressed: Get.back<void>,
              ),
            ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 92,
            right: 16,
            child: RideIconButton(
              icon: Icons.my_location_rounded,
              tooltip: 'تحديد موقعي',
              onPressed: widget.controller.useCurrentLocation,
            ),
          ),
          Positioned(
            left: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 150,
            width: 310,
            child: IgnorePointer(
              ignoring: !_showSaved,
              child: AnimatedSlide(
                offset: _showSaved ? Offset.zero : const Offset(-.18, .08),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _showSaved ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 14,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text(
                                  'الأماكن المحفوظة',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'إغلاق',
                                onPressed: () =>
                                    setState(() => _showSaved = false),
                                icon: Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const RecentPlacesList(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 82,
            child: RideIconButton(
              icon: _showSaved ? Icons.close_rounded : Icons.bookmark_rounded,
              tooltip: _showSaved ? 'إغلاق الأماكن' : 'الأماكن المحفوظة',
              onPressed: () => setState(() => _showSaved = !_showSaved),
            ),
          ),
          Positioned(
            left: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: Obx(
              () => RideIconButton(
                iconWidget: const DirectionalArrowIcon(forward: true),
                tooltip: 'تأكيد بيانات المسار',
                backgroundColor: widget.controller.canContinueLocationFlow
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surface,
                foregroundColor: widget.controller.canContinueLocationFlow
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).disabledColor,
                onPressed: widget.controller.canContinueLocationFlow
                    ? widget.controller.openAddressDetails
                    : () {},
              ),
            ),
          ),
        ],
      );
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
                            style: TextStyle(fontWeight: FontWeight.w900),
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
        title: 'ابحث عن موقع',
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
      map: Obx(
        () => AppGoogleMap(
          markers: controller.markers,
          polylines: controller.polylines,
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
                    style: TextStyle(fontWeight: FontWeight.w800),
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
                        style: TextStyle(fontWeight: FontWeight.w900),
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
