import 'dart:ui' as ui;

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
          await rideController.loadNearbyDrivers(
              center: controller.pickup.value);
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
            mapType: controller.mapType.value,
            followTarget: controller.pickup.value,
            additionalMarkers: controller.markers,
            polylines: controller.polylines,
            onMapCreated: controller.onMapCreated,
            onTap: controller.selectMapPoint,
            minimumCardTop: 230,
            useModernMapStyle: true,
          ),
        ),
        showPanel: false,
        panel: const SizedBox.shrink(),
        embedded: widget.isMainShell,
        top:
            widget.isMainShell ? const RideHomeHeader(routePicker: true) : null,
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

  Future<void> _showMapTypeOptions() async {
    final selected = widget.controller.mapType.value;
    const options = <(MapType, String, IconData)>[
      (MapType.normal, 'الخريطة العادية', Icons.map_outlined),
      (MapType.satellite, 'القمر الصناعي', Icons.satellite_alt_outlined),
      (MapType.terrain, 'التضاريس', Icons.terrain_rounded),
      (MapType.hybrid, 'هجين', Icons.layers_outlined),
    ];
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 8, bottom: 8),
              child: Text(
                'طبقات الخريطة',
                style: TextStyle(
                  color: Color(0xFF102C50),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...options.map((option) {
              final (type, label, icon) = option;
              final isSelected = selected == type;
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(
                  icon,
                  color: isSelected
                      ? const Color(0xFF087AC1)
                      : const Color(0xFF607B95),
                ),
                title: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF102C50),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF087AC1),
                      )
                    : null,
                onTap: () {
                  widget.controller.mapType.value = type;
                  Get.back<void>();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          const _SkylineMapBackdrop(),
          Obx(() {
            final serviceUnavailable =
                widget.controller.serviceAreaAvailable.value == false;
            final topOffset = widget.showBackButton
                ? 12.0
                : serviceUnavailable
                    ? 142.0
                    : 112.0;
            return Positioned(
              top: MediaQuery.paddingOf(context).top + topOffset,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xF2FFFFFF),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFD2E3F0)),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x24102C50),
                              blurRadius: 20,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(9),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  const InteractiveRouteFieldsOverlay(),
                                  const SizedBox(height: 9),
                                  _buildFindDriverButton(context),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      RideProcessStepper(
                        currentStep: 1,
                        compact: true,
                        surfaceColor: const Color(0xEFFFFFFF),
                        foregroundColor: const Color(0xFF102C50),
                        activeColor: const Color(0xFF087AC1),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
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
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RideIconButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'تحديد موقعي',
                  foregroundColor: const Color(0xFF102C50),
                  onPressed: widget.controller.useCurrentLocation,
                ),
                const SizedBox(height: 10),
                RideIconButton(
                  icon: Icons.layers_outlined,
                  tooltip: 'طبقات الخريطة',
                  foregroundColor: const Color(0xFF102C50),
                  onPressed: _showMapTypeOptions,
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 172,
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
            bottom: MediaQuery.paddingOf(context).bottom + 104,
            child: RideIconButton(
              icon: _showSaved ? Icons.close_rounded : Icons.bookmark_rounded,
              tooltip: _showSaved ? 'إغلاق الأماكن' : 'الأماكن المحفوظة',
              onPressed: () => setState(() => _showSaved = !_showSaved),
            ),
          ),
        ],
      );

  Widget _buildFindDriverButton(BuildContext context) => Obx(() {
        final enabled = widget.controller.canContinueLocationFlow;
        final foreground = enabled ? Colors.white : const Color(0xFF6F8295);
        final background =
            enabled ? const Color(0xFF102C50) : const Color(0xFFDCE6EF);

        return Semantics(
          button: true,
          enabled: enabled,
          label: 'البحث عن أقرب سائق',
          child: Material(
            color: background,
            elevation: enabled ? 2 : 0,
            shadowColor: const Color(0x33102C50),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled
                  ? () {
                      if (widget.controller.serviceAreaAvailable.value ==
                          false) {
                        Get.snackbar(
                          'الخدمة غير متوفرة',
                          'الخدمة غير متوفرة في منطقتك حالياً.',
                        );
                        return;
                      }
                      widget.controller.openAddressDetails();
                    }
                  : null,
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 42),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.directions_car_filled_rounded,
                            size: 24,
                            color: foreground,
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              'البحث عن أقرب سائق',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PositionedDirectional(
                      end: 12,
                      child: IconTheme(
                        data: IconThemeData(color: foreground),
                        child: const DirectionalArrowIcon(forward: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
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

class _SkylineMapBackdrop extends StatelessWidget {
  const _SkylineMapBackdrop();

  @override
  Widget build(BuildContext context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 248,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0xBFEAF5FF),
                        Color(0x8AEAF5FF),
                        Color(0x55F5F8FB),
                        Color(0x00F5F8FB),
                      ],
                      stops: <double>[0, .38, .76, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AspectRatio(
                    aspectRatio: 800 / 267,
                    child: Opacity(
                      opacity: .62,
                      child: Image.asset(
                        'assets/images/branding/sanaa_city_skyline.png',
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
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
