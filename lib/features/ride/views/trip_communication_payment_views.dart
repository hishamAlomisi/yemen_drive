import 'dart:async';
import '../../../shared/widgets/ride_waiting_panel.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/config/app_environment.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_google_map.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/ride_route_change_panel.dart';
import '../../../shared/widgets/ride_route_destination_picker.dart';
import '../controllers/chat_controller.dart';
import '../controllers/payment_controller.dart';
import '../controllers/ride_controller.dart';
import '../controllers/safety_recording_controller.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../location_selection/repositories/location_search_repository.dart';
import '../models/ride_models.dart';
import '../ride_routes.dart';
import '../widgets/ride_common_widgets.dart';
import '../widgets/external_payment_methods.dart';
import '../widgets/ride_map_shell.dart';
import '../widgets/ride_payment_widgets.dart';
import '../widgets/ride_trip_widgets.dart';

class DriverLocationPage extends StatefulWidget {
  const DriverLocationPage({super.key});

  @override
  State<DriverLocationPage> createState() => _DriverLocationPageState();
}

class _DriverLocationPageState extends State<DriverLocationPage> {
  final RideController controller = Get.find<RideController>();
  bool _isSubmittingCashShortfallDecision = false;
  bool _isFollowingLiveRoute = true;
  int _liveRouteFocusRevision = 0;
  Worker? _cashShortfallOpenWorker;

  @override
  void initState() {
    super.initState();
    _cashShortfallOpenWorker = ever<int?>(
      controller.cashShortfallApprovalToOpen,
      _openRequestedCashShortfall,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openRequestedCashShortfall(
        controller.cashShortfallApprovalToOpen.value,
      );
      if (!mounted ||
          controller.hasShownTripSharePrompt ||
          controller.pendingRatingRideId.value != null) return;
      controller.hasShownTripSharePrompt = true;
      _showTripSharePrompt();
    });
  }

  void _openRequestedCashShortfall(int? approvalId) {
    if (!mounted || approvalId == null || (Get.isDialogOpen ?? false)) return;
    final approval = controller.cashCollectionApproval.value;
    if (approval == null ||
        int.tryParse('${approval['id'] ?? ''}') != approvalId ||
        '${approval['status']}' != '0') {
      return;
    }
    controller.cashShortfallApprovalToOpen.value = null;
    unawaited(_showCashShortfallDecision(approval));
  }

  @override
  void dispose() {
    _cashShortfallOpenWorker?.dispose();
    super.dispose();
  }

  void _toggleLiveRouteFollowing() {
    setState(() {
      _isFollowingLiveRoute = !_isFollowingLiveRoute;
      if (_isFollowingLiveRoute) _liveRouteFocusRevision++;
    });
  }

  Future<RideRouteDestination?> _selectChangedDestination() {
    final location = Get.find<LocationController>();
    final search = Get.find<LocationSearchRepository>();
    RideRouteDestination destination(LocationSearchResult value) =>
        RideRouteDestination(
          latitude: value.location.latitude,
          longitude: value.location.longitude,
          label: value.formattedAddress.trim().isNotEmpty
              ? value.formattedAddress
              : value.title,
        );
    return Navigator.of(context).push<RideRouteDestination>(MaterialPageRoute(
      builder: (_) => RideRouteDestinationPicker(
        initialTarget: location.destination.value ??
            location.pickup.value ??
            const LatLng(15.3694, 44.1910),
        search: (query) async => (await search.search(query))
            .map(destination)
            .toList(growable: false),
        reverseGeocode: (point) async {
          final value = await search.reverseGeocode(point);
          return value == null ? null : destination(value);
        },
      ),
    ));
  }

  Future<void> _refreshChangedRoute() async {
    await controller.refreshActiveRide(requireSuccess: true);
    if (Get.isRegistered<PaymentController>()) {
      await Get.find<PaymentController>().loadPaymentSummary();
    }
    if (mounted) setState(() => _liveRouteFocusRevision++);
  }

  Future<void> _showTripSharePrompt() => Get.dialog<void>(
        _TripSharePrompt(
          onShare: _shareTrip,
          onLater: Get.back<void>,
        ),
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .52),
      );

  Future<void> _shareTrip() async {
    final draft = controller.currentDraft.value;
    final destination = draft?.destinationAddressName.trim().isNotEmpty == true
        ? draft!.destinationAddressName.trim()
        : draft?.destinationAddress.trim().isNotEmpty == true
            ? draft!.destinationAddress.trim()
            : 'الوجهة المحددة';
    final driver = controller.acceptedOffer.value?.driverName ?? 'driver'.tr;
    final safety = Get.find<SafetyRecordingController>();
    final shareUrl = await safety.createLiveShareLink();
    if (shareUrl == null) {
      Get.snackbar('مشاركة الرحلة', safety.error.value);
      return;
    }
    final message = '${'shared_trip_message'.trParams(<String, String>{
          'destination': destination,
          'driver': driver,
        })}\n$shareUrl';
    await SharePlus.instance.share(ShareParams(text: message));
    if (Get.isDialogOpen ?? false) Get.back<void>();
  }

  Future<void> _showCancelDecision() {
    final status = controller.activeRideStatus.value;
    if (status == 'Completed' || status == '6') {
      Get.snackbar(
        'لا يمكن إلغاء الرحلة',
        'اكتملت الرحلة، ولا يمكن إلغاءها أو طلب استرداد مبلغها.',
        snackPosition: SnackPosition.TOP,
      );
      return Future<void>.value();
    }
    if (status == 'DriverEnRoute' ||
        status == '4' ||
        status == 'DriverArrived' ||
        status == '9') {
      return Get.toNamed<void>(RideRoutes.rideCancel) ?? Future<void>.value();
    }
    return Get.dialog<void>(
      _RideCancelDecisionDialog(
        offer: controller.acceptedOffer.value,
        onWait: Get.back<void>,
        onSupport: () {
          Get.back<void>();
          final driverName =
              controller.acceptedOffer.value?.driverName ?? 'driver'.tr;
          Get.snackbar(
            'contact_driver'.tr,
            'driver_contact_unavailable'.trParams(<String, String>{
              'driver': driverName,
            }),
            snackPosition: SnackPosition.TOP,
          );
        },
        onCancel: () {
          Get.back<void>();
          Get.toNamed<void>(RideRoutes.rideCancel);
        },
      ),
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .52),
    );
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final location = Get.find<LocationController>();
        final canProceedToPayment =
            controller.activeRideStatus.value == 'Completed' ||
                controller.activeRideStatus.value == '6' ||
                controller.customerPaymentEnabled.value;
        final paymentReadyForReview =
            (controller.activeRideStatus.value == 'Completed' ||
                    controller.activeRideStatus.value == '6') &&
                controller.activeRidePaymentCompleted.value;
        final cashApproval = controller.cashCollectionApproval.value;
        final approvalPending =
            cashApproval != null && '${cashApproval['status']}' == '0';
        final lockBackNavigation = <String>{
          'DriverAssigned',
          'DriverEnRoute',
          'DriverArrived',
          'InProgress',
          'Completed',
          '3',
          '4',
          '5',
          '6',
          '9',
        }.contains(controller.activeRideStatus.value);
        final statusLabel = switch (controller.activeRideStatus.value) {
          'DriverAssigned' || '3' => 'تم تعيين السائق',
          'DriverEnRoute' || '4' => 'السائق في الطريق',
          'DriverArrived' || '9' => 'وصل السائق، يرجى التوجه إليه',
          'InProgress' || '5' => 'الرحلة جارية',
          'Completed' || '6' => 'تم الوصول',
          _ => 'جاري تحديث حالة الرحلة',
        };
        final liveRouteBounds =
            controller.trackingFocusBounds ?? location.selectedRouteBounds;
        final gps = controller.latestDriverGpsSample;
        return PopScope<void>(
          canPop: !lockBackNavigation,
          child: RideMapShell(
            map: AppGoogleMap(
              initialTarget:
                  location.pickup.value ?? const LatLng(15.3694, 44.1910),
              markers: <Marker>{
                // The pickup marker is the customer's personal marker.
                // Do not add a second generic passenger pin during live
                // tracking, otherwise the destination becomes unclear.
                ...location.markers,
                ...controller.trackingMarkers,
              },
              polylines: controller.trackingPolylines.isNotEmpty
                  ? controller.trackingPolylines
                  : location.polylines,
              mapType: location.mapType.value,
              useModernMapStyle: true,
              focusTarget: _isFollowingLiveRoute && gps != null
                  ? LatLng(gps.location.latitude, gps.location.longitude)
                  : null,
              focusTargetZoom: 17,
              mapPadding: EdgeInsets.only(
                  bottom: MediaQuery.sizeOf(context).height * .4),
              // The bounds contain the actual GPS position plus the remaining
              // road route. A passenger can pause this automatic camera move
              // to inspect the map, then enable it again from the map button.
              focusBounds:
                  _isFollowingLiveRoute && gps == null ? liveRouteBounds : null,
              focusBoundsPadding: 104,
              focusBoundsRevision: _liveRouteFocusRevision,
              focusBoundsUpdateInterval: const Duration(milliseconds: 650),
            ),
            showRoute: true,
            showMarker: false,
            panelMaxHeightFactor: .65,
            allowPanelCollapse: true,
            mapAction: RideIconButton(
              icon: _isFollowingLiveRoute
                  ? Icons.gps_fixed_rounded
                  : Icons.gps_not_fixed_rounded,
              tooltip: _isFollowingLiveRoute
                  ? 'إيقاف تتبع مسار السائق'
                  : 'تتبع مسار السائق',
              onPressed: _toggleLiveRouteFollowing,
            ),
            mapActionAtStart: true,
            panelFooter: AppButton(
              label: approvalPending
                  ? 'موافقة مطلوبة لفرق الدفع'
                  : paymentReadyForReview
                      ? 'متابعة إلى التقييم'
                      : canProceedToPayment
                          ? 'متابعة إلى الدفع'
                          : 'بانتظار اكتمال الرحلة',
              onPressed: approvalPending
                  ? () => _showCashShortfallDecision(cashApproval)
                  : paymentReadyForReview
                      ? () => Get.toNamed<void>(RideRoutes.review)
                      : canProceedToPayment
                          ? () => Get.toNamed<void>(RideRoutes.payment)
                          : null,
            ),
            top: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                lockBackNavigation
                    ? const SizedBox(width: 48)
                    : const RideBackButton(),
                RideStatusPill(
                  label: statusLabel,
                  icon: Icons.local_taxi_rounded,
                ),
              ],
            ),
            panel: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DriverCard(status: statusLabel),
                const DriverCancellationDecisionCard(),
                const SizedBox(height: AppSpacing.sm),
                RouteSummaryCard(compact: true),
                if (int.tryParse(controller.currentRideId ?? '')
                    case final int rideId)
                  RideWaitingPanel(
                      rideId: rideId,
                      onChanged: () {
                        unawaited(controller.refreshActiveRide());
                        if (Get.isRegistered<PaymentController>()) {
                          unawaited(Get.find<PaymentController>()
                              .loadPaymentSummary());
                        }
                      }),
                if ((controller.activeRideStatus.value == 'InProgress' ||
                        controller.activeRideStatus.value == '5') &&
                    int.tryParse(controller.currentRideId ?? '') != null)
                  RideRouteChangePanel(
                    rideId: int.parse(controller.currentRideId!),
                    selectDestination: _selectChangedDestination,
                    onRouteChanged: _refreshChangedRoute,
                  ),
                const SizedBox(height: AppSpacing.md),
                TripEmergencyActions(
                  onShareTrip: _shareTrip,
                  onCancelRide: _showCancelDecision,
                ),
              ],
            ),
          ),
        );
      });

  Future<void> _showCashShortfallDecision(Map<String, Object?> approval) async {
    if (_isSubmittingCashShortfallDecision || (Get.isDialogOpen ?? false)) {
      return;
    }
    final approvalId = int.tryParse('${approval['id']}');
    if (approvalId == null) return;
    final amount = approval['walletDebitAmount'] ?? 0;
    final payment = Get.find<PaymentController>();
    await Get.dialog<void>(AlertDialog(
      title: const Text('موافقة مطلوبة'),
      content: Text(
          'استلم السائق مبلغاً أقل من الإجمالي. هل توافق على خصم $amount ر.ي من محفظتك لإتمام الدفع؟'),
      actions: [
        TextButton(
            onPressed: () async {
              await _submitCashShortfallDecision(
                payment: payment,
                approvalId: approvalId,
                accept: false,
              );
            },
            child: const Text('رفض')),
        FilledButton(
            onPressed: () async {
              await _submitCashShortfallDecision(
                payment: payment,
                approvalId: approvalId,
                accept: true,
              );
            },
            child: const Text('موافقة')),
      ],
    ));
  }

  Future<void> _submitCashShortfallDecision({
    required PaymentController payment,
    required int approvalId,
    required bool accept,
  }) async {
    if (_isSubmittingCashShortfallDecision) return;
    _isSubmittingCashShortfallDecision = true;

    // Close the prompt before awaiting the network request. This prevents a
    // customer from submitting the same financial decision more than once.
    if (Get.isDialogOpen ?? false) Get.back<void>();
    try {
      final completed = await payment.decideCashShortfall(
        approvalId: approvalId,
        accept: accept,
      );
      if (completed) await controller.refreshActiveRide();
    } finally {
      _isSubmittingCashShortfallDecision = false;
    }
  }
}

class _RideCancelDecisionDialog extends StatelessWidget {
  const _RideCancelDecisionDialog({
    required this.offer,
    required this.onWait,
    required this.onSupport,
    required this.onCancel,
  });

  final DriverOffer? offer;
  final VoidCallback onWait;
  final VoidCallback onSupport;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final driverName = offer?.driverName ?? 'driver'.tr;
    final eta = offer?.etaMinutes ?? 3;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: isDark ? .97 : .98),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.primary.withValues(alpha: .34),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? .38 : .20),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary.withValues(alpha: .14),
                      border: Border.all(color: colors.primary, width: 2),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 40,
                      color: colors.primary,
                    ),
                  ),
                  if (offer != null)
                    PositionedDirectional(
                      start: -12,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: .38),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              offer!.rating.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'driver_arrives_in'.trParams(<String, String>{
                  'driver': driverName,
                  'minutes': '$eta',
                }),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'wait_for_driver_hint'.tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CancelDecisionAction(
                      icon: Icons.close_rounded,
                      label: 'confirm_cancel_ride'.tr,
                      color: colors.error,
                      onTap: onCancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CancelDecisionAction(
                      icon: Icons.support_agent_rounded,
                      label: 'contact_driver'.tr,
                      color: colors.primary,
                      onTap: onSupport,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'wait_for_driver'.tr,
                leading: Icon(Icons.schedule_rounded, size: 19),
                onPressed: onWait,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CancelDecisionAction extends StatelessWidget {
  const _CancelDecisionAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: .13),
                  border: Border.all(color: color.withValues(alpha: .32)),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
              ),
            ],
          ),
        ),
      );
}

class _TripSharePrompt extends StatelessWidget {
  const _TripSharePrompt({required this.onShare, required this.onLater});

  final VoidCallback onShare;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: isDark ? .97 : .98),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.primary.withValues(alpha: .38),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? .38 : .20),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _TripShareVisual(),
              const SizedBox(height: 16),
              Text(
                'share_trip_live_title'.tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'share_trip_live_hint'.tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 17),
              AppButton(
                label: 'share_trip'.tr,
                size: AppButtonSize.medium,
                leading: Icon(Icons.ios_share_rounded, size: 19),
                onPressed: onShare,
              ),
              const SizedBox(height: 7),
              AppButton(
                label: 'not_now'.tr,
                size: AppButtonSize.small,
                variant: AppButtonVariant.text,
                onPressed: onLater,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripShareVisual extends StatelessWidget {
  const _TripShareVisual();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: .22)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            Icons.map_rounded,
            size: 112,
            color: colors.primary.withValues(alpha: .30),
          ),
          PositionedDirectional(
            start: 70,
            bottom: 26,
            child: Icon(
              Icons.location_on_rounded,
              size: 35,
              color: colors.secondary,
            ),
          ),
          PositionedDirectional(
            end: 72,
            top: 25,
            child: Icon(
              Icons.location_on_rounded,
              size: 35,
              color: colors.primary,
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.inverseSurface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 3),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: .22),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(
              Icons.ios_share_rounded,
              color: colors.onInverseSurface,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class RideChatPage extends GetView<ChatController> {
  const RideChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final offer = Get.find<RideController>().acceptedOffer.value;
    return RidePageFrame(
      title: offer?.driverName ?? 'المحادثة',
      resizeToAvoidBottomInset: true,
      actions: <Widget>[
        IconButton(
          onPressed: () => Get.toNamed<void>(RideRoutes.call),
          tooltip: 'اتصال',
          icon: Icon(Icons.call_outlined),
        ),
      ],
      body: Column(
        children: <Widget>[
          const _ChatDriverStatus(),
          Expanded(
            child: Obx(
              () => controller.isLoading.value && controller.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : controller.messages.isEmpty
                      ? const Center(child: Text('لا توجد رسائل بعد.'))
                      : ListView.separated(
                          controller: controller.scrollController,
                          reverse: false,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md),
                          itemCount: controller.messages.length +
                              (controller.hasOlderMessages.value ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            if (controller.hasOlderMessages.value &&
                                index == 0) {
                              return Center(
                                child: TextButton.icon(
                                  onPressed: controller.isLoadingOlder.value
                                      ? null
                                      : controller.loadOlderMessages,
                                  icon: controller.isLoadingOlder.value
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.history_rounded),
                                  label: const Text('تحميل رسائل أقدم'),
                                ),
                              );
                            }
                            final messageIndex =
                                controller.hasOlderMessages.value
                                    ? index - 1
                                    : index;
                            return _MessageBubble(
                                message: controller.messages[messageIndex]);
                          },
                        ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      controller: controller.messageController,
                      hint: 'اكتب رسالتك...',
                      textInputAction: TextInputAction.send,
                      prefixIcon: Icon(Icons.emoji_emotions_outlined),
                      onSubmitted: (_) => controller.sendMessage(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Obx(
                    () => Material(
                      color: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: controller.isSending.value
                            ? null
                            : controller.sendMessage,
                        tooltip: 'إرسال',
                        color: Theme.of(context).colorScheme.onPrimary,
                        icon: Icon(Icons.send_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DriverCallPage extends StatelessWidget {
  const DriverCallPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        showBack: false,
        body: _CallLayout(
          status: 'جارٍ الاتصال...',
          primaryIcon: Icons.call_rounded,
          primaryColor: const Color(0xFF2E7D32),
          primaryLabel: 'بدء المكالمة',
          onPrimary: () => Get.offNamed<void>(RideRoutes.activeCall),
          onClose: () => Get.back<void>(),
        ),
      );
}

class ActiveCallPage extends StatelessWidget {
  const ActiveCallPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        showBack: false,
        body: _CallLayout(
          status: '00:42',
          primaryIcon: Icons.call_end_rounded,
          primaryColor: AppColors.error,
          primaryLabel: 'إنهاء المكالمة',
          onPrimary: () => Get.offNamed<void>(RideRoutes.payment),
          onClose: () => Get.offNamed<void>(RideRoutes.payment),
          active: true,
        ),
      );
}

class RidePaymentPage extends GetView<PaymentController> {
  const RidePaymentPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        title: 'طريقة الدفع',
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  const RideSectionHeader(
                    title: 'اختر طريقة الدفع',
                    subtitle: 'راجع المبلغ واختر الوسيلة المناسبة لك.',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Obx(() => controller.cashPaymentConfirmed.value
                        ? AppCard(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .14),
                            borderColor: Theme.of(context).colorScheme.primary,
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.verified_rounded,
                                    color: AppColors.accent(context), size: 28),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                    child: Text(
                                        'تم قبض مبلغ الرحلة نقداً من قبل السائق. لا حاجة لاختيار وسيلة دفع أخرى.',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))),
                              ],
                            ),
                          )
                        : PaymentMethodTile(
                            id: 'cash',
                            title: 'نقداً',
                            subtitle: controller.cashRequestStatus.value == 0
                                ? 'بانتظار تأكيد السائق للاستلام'
                                : controller.cashRequestStatus.value == 1
                                    ? 'أكد السائق؛ يجري تسجيل التحصيل'
                                    : controller.cashRequestStatus.value == 2
                                        ? 'لم يؤكد السائق الاستلام؛ اختر وسيلة أخرى'
                                        : 'يرسل طلب تأكيد إلى السائق',
                            icon: Icons.payments_outlined,
                          )),
                    Obx(() => PaymentMethodTile(
                          id: 'wallet',
                          title: 'محفظة يمن درايف',
                          subtitle:
                              'الرصيد المتاح ${controller.walletBalance.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                          icon: Icons.account_balance_wallet_outlined,
                        )),
                    Obx(() => ExternalPaymentMethodsTile(
                          selected: controller.selectedMethod.value,
                          enabled: !controller.cashPaymentConfirmed.value &&
                              !controller.isPaying.value,
                          onSelected: controller.selectMethod,
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const PriceSummary(),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Obx(() => AppButton(
                    label: controller.isPaying.value
                        ? 'جارٍ إتمام الدفع...'
                        : controller.cashPaymentConfirmed.value
                            ? controller.rideCompletedByDriver.value
                                ? 'متابعة إلى التقييم'
                                : 'تم الدفع — بانتظار إنهاء السائق'
                            : 'تأكيد ودفع ${controller.totalDue.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                    leading: const Icon(Icons.lock_outline_rounded),
                    onPressed: controller.isPaying.value
                        ? null
                        : controller.cashPaymentConfirmed.value
                            ? controller.finishCollectedCashRide
                            : controller.pay,
                  )),
            ),
          ],
        ),
      );
}

class ActiveRidePage extends StatelessWidget {
  const ActiveRidePage({super.key});

  // Keep the legacy route on the same real-time screen. The old standalone
  // page only drew a static route and placeholder trip details.
  @override
  Widget build(BuildContext context) => const DriverLocationPage();
}

class RideReviewPage extends GetView<PaymentController> {
  const RideReviewPage({super.key});

  @override
  Widget build(BuildContext context) => PopScope<void>(
      canPop: false,
      child: RidePageFrame(
        showBack: false,
        title: 'تقييم الرحلة',
        footer: Obx(() => AppButton(
              label: controller.isSubmittingReview.value
                  ? 'جارٍ إرسال التقييم…'
                  : 'إرسال التقييم',
              onPressed: controller.isSubmittingReview.value
                  ? null
                  : controller.submitReview,
            )),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .2),
                  child: Icon(Icons.person_rounded, size: 52),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'كيف كانت تجربتك مع السائق؟',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'أكمل تقييم هذه الرحلة قبل حجز رحلة جديدة.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              const RatingStars(),
              const SizedBox(height: AppSpacing.md),
              const Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  ReviewTag(label: 'قيادة آمنة'),
                  ReviewTag(label: 'سيارة نظيفة'),
                  ReviewTag(label: 'سائق محترم'),
                  ReviewTag(label: 'وصول سريع'),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: controller.reviewController,
                label: 'ملاحظات إضافية',
                hint: 'اكتب تعليقاً يساعدنا على تحسين الخدمة',
                minLines: 3,
                maxLines: 5,
              ),
            ],
          ),
        ),
      ));
}

class DriverCancellationDecisionCard extends GetView<RideController> {
  const DriverCancellationDecisionCard({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
        final request = controller.driverCancellationRequest.value;
        if (request == null ||
            request['requestedByDriver'] != true ||
            request['canDecide'] != true) return const SizedBox.shrink();
        final busy = controller.isDecidingDriverCancellation.value;
        return Card(
          shape: RoundedRectangleBorder(
            side: BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('يطلب السائق إلغاء الرحلة',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('${request['reason'] ?? ''}'),
                  const Text('تستمر الرحلة ما لم توافق على الإلغاء.'),
                  FilledButton(
                    key: const ValueKey('approve-driver-cancellation'),
                    onPressed: busy
                        ? null
                        : () =>
                            controller.decideDriverCancellation(accept: true),
                    child: const Text('الموافقة على إلغاء الرحلة'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('reject-driver-cancellation'),
                    onPressed: busy
                        ? null
                        : () =>
                            controller.decideDriverCancellation(accept: false),
                    child: const Text('رفض الإلغاء ومتابعة الرحلة'),
                  ),
                  if (busy) const LinearProgressIndicator(),
                ]),
          ),
        );
      });
}

class RideThanksPage extends StatelessWidget {
  const RideThanksPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        showBack: false,
        body: RideSuccessView(
          title: 'شكراً لركوبك معنا!',
          message: 'وصلت إلى وجهتك بأمان. نتمنى أن نراك في رحلة جديدة قريباً.',
          actionLabel: 'احجز رحلة جديدة',
          action: () {
            Get.find<RideController>().prepareNewRide();
            Get.offAllNamed<void>(RideRoutes.homeTransport);
          },
        ),
      );
}

class _ChatDriverStatus extends StatelessWidget {
  const _ChatDriverStatus();

  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = Get.find<RideController>();
        final driverName = ride.assignedDriverName.value.isNotEmpty
            ? ride.assignedDriverName.value
            : ride.acceptedOffer.value?.driverName ?? 'السائق المعين';
        final routeEtaSeconds = ride.trackingRouteDurationSeconds.value;
        final eta = routeEtaSeconds > 0
            ? (routeEtaSeconds + 59) ~/ 60
            : ride.acceptedOffer.value?.etaMinutes;
        final remainingMeters = ride.trackingRouteDistanceMeters.value;
        final nextStep = ride.trackingNextStepInstruction.value;
        final nextStepMeters = ride.trackingNextStepDistanceMeters.value;
        return AppCard(
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 10,
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 19,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(
                  Icons.person_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      driverName,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      remainingMeters > 0
                          ? 'متبقي نحو ${(remainingMeters / 1000).toStringAsFixed(1)} كم · التتبع مباشر'
                          : 'تحديث حالة الرحلة مباشر',
                      style: TextStyle(color: AppColors.success),
                    ),
                    if (nextStep.isNotEmpty)
                      Text(
                        '${nextStepMeters > 0 ? 'بعد $nextStepMeters م: ' : ''}$nextStep',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              RideStatusPill(
                label: eta == null || eta <= 0 ? '—' : '$eta دقائق',
                icon: Icons.schedule_rounded,
              ),
            ],
          ),
        );
      });
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final RideChatMessage message;

  @override
  Widget build(BuildContext context) => Align(
        alignment: message.isMine
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .72,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: message.isMine
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .08),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(message.isMine ? 18 : 4),
                bottomRight: Radius.circular(message.isMine ? 4 : 18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    message.text,
                    style: TextStyle(
                      color: message.isMine
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.timeLabel,
                    style: TextStyle(
                      color: message.isMine
                          ? Theme.of(context)
                              .colorScheme
                              .onPrimary
                              .withValues(alpha: .72)
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: .5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CallLayout extends StatelessWidget {
  const _CallLayout({
    required this.status,
    required this.primaryIcon,
    required this.primaryColor,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onClose,
    this.active = false,
  });

  final String status;
  final IconData primaryIcon;
  final Color primaryColor;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onClose;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.topStart,
            child: IconButton(
              onPressed: onClose,
              tooltip: 'إغلاق',
              icon: Icon(Icons.close_rounded),
            ),
          ),
          const Spacer(),
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: .2),
            ),
            child: Icon(Icons.person_rounded, size: 82),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'محمد اليمني',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(status, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (active)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                RideIconButton(
                  icon: Icons.mic_off_outlined,
                  tooltip: 'كتم الصوت',
                  onPressed: () {},
                ),
                const SizedBox(width: AppSpacing.lg),
                RideIconButton(
                  icon: Icons.volume_up_outlined,
                  tooltip: 'مكبر الصوت',
                  onPressed: () {},
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.xl),
          Semantics(
            button: true,
            label: primaryLabel,
            child: Material(
              color: primaryColor,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onPrimary,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: Icon(primaryIcon, color: Colors.white, size: 36),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(primaryLabel, style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
        ],
      );
}
