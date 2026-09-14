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
import '../../account/models/account_models.dart';
import '../controllers/chat_controller.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../controllers/payment_controller.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../ride_routes.dart';
import '../widgets/ride_common_widgets.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller.hasShownTripSharePrompt) return;
      controller.hasShownTripSharePrompt = true;
      _showTripSharePrompt();
    });
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
    final message = 'shared_trip_message'.trParams(<String, String>{
      'destination': destination,
      'driver': driver,
    });
    await SharePlus.instance.share(ShareParams(text: message));
    if (Get.isDialogOpen ?? false) Get.back<void>();
  }

  Future<void> _showCancelDecision() => Get.dialog<void>(
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
            controller.cancelActiveRide('إلغاء الرحلة أثناء توجه السائق');
          },
        ),
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .52),
      );

  @override
  Widget build(BuildContext context) => Obx(() {
        final location = Get.find<LocationController>();
        final canProceedToPayment =
            controller.activeRideStatus.value == 'Completed' ||
                controller.activeRideStatus.value == '6';
        final useDevelopmentTrackingFallback = !AppEnvironment.isProduction;
        final statusLabel = switch (controller.activeRideStatus.value) {
          'DriverAssigned' || '3' => 'تم تعيين السائق',
          'DriverEnRoute' || '4' => 'السائق في الطريق',
          'InProgress' || '5' => 'الرحلة جارية',
          'Completed' || '6' => 'تم الوصول',
          _ => 'جاري تحديث حالة الرحلة',
        };
        return RideMapShell(
          processStep: 4,
          map: useDevelopmentTrackingFallback
              ? const _DevelopmentTrackingMap()
              : AppGoogleMap(
                  initialTarget:
                      location.pickup.value ?? const LatLng(15.3694, 44.1910),
                  markers: <Marker>{
                    ...location.markers,
                    ...controller.trackingMarkers,
                  },
                  followTarget: controller.trackedDriver.value == null
                      ? null
                      : LatLng(
                          controller.trackedDriver.value!.location.latitude,
                          controller.trackedDriver.value!.location.longitude,
                        ),
                  polylines: location.polylines,
                  showDemoMarker: false,
                  showDemoRoute: false,
                ),
          showRoute: true,
          showMarker: false,
          panelMaxHeightFactor: .58,
          panelFooter: AppButton(
            label: canProceedToPayment
                ? 'متابعة إلى الدفع'
                : 'بانتظار اكتمال الرحلة',
            onPressed: canProceedToPayment
                ? () => Get.toNamed<void>(RideRoutes.payment)
                : null,
          ),
          top: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const RideBackButton(),
              RideStatusPill(
                label: statusLabel,
                icon: Icons.local_taxi_rounded,
              ),
            ],
          ),
          panel: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const RidePanelHandle(),
              const DriverCard(),
              const SizedBox(height: AppSpacing.sm),
              RouteSummaryCard(compact: true),
              const SizedBox(height: AppSpacing.md),
              TripEmergencyActions(
                onShareTrip: _shareTrip,
                onCancelRide: _showCancelDecision,
              ),
            ],
          ),
        );
      });
}

class _DevelopmentTrackingMap extends StatelessWidget {
  const _DevelopmentTrackingMap();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.mapLandLight,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.location_searching_rounded, size: 42),
                SizedBox(height: 10),
                Text(
                  'متابعة موقع السائق التجريبية',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 6),
                Text(
                  'الخريطة الحية تعمل عند تجهيز بيئة الخرائط الفعلية.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
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
                                fontWeight: FontWeight.w900,
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
                  fontWeight: FontWeight.w900,
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
                      fontWeight: FontWeight.w800,
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
                  fontWeight: FontWeight.w900,
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
              () => ListView.separated(
                reverse: false,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                itemCount: controller.messages.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) =>
                    _MessageBubble(message: controller.messages[index]),
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
                  Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: controller.sendMessage,
                      tooltip: 'إرسال',
                      color: Colors.black,
                      icon: Icon(Icons.send_rounded),
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
                    subtitle: 'ستتم معالجة العملية بأمان عند بدء الرحلة.',
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
                    Obx(
                      () => AppCard(
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: controller.useWalletBalance.value,
                          activeColor: AppColors.primaryDark,
                          onChanged: (value) {
                            controller.useWalletBalance.value = value;
                          },
                          title: const Text(
                            'استخدام رصيد المحفظة أولاً',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'يُخصم المتبقي من طريقة الدفع المختارة.',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const PaymentMethodTile(
                      id: 'cash',
                      title: 'نقداً',
                      subtitle: 'ادفع للسائق عند الوصول',
                      icon: Icons.payments_outlined,
                    ),
                    Obx(() => PaymentMethodTile(
                          id: 'wallet',
                          title: 'محفظة يمن درايف',
                          subtitle:
                              'الرصيد المتاح ${controller.walletBalance.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                          icon: Icons.account_balance_wallet_outlined,
                        )),
                    for (PaymentMethodItem items
                        in AppEnvironment.paymentMethods)
                      PaymentMethodTile(
                        id: items.id,
                        title: items.label,
                        subtitle: items.subtitle,
                        icon: items.icon,
                      ),
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
                        : 'تأكيد ودفع ${controller.totalDue.value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                    leading: const Icon(Icons.lock_outline_rounded),
                    onPressed:
                        controller.isPaying.value ? null : controller.pay,
                  )),
            ),
          ],
        ),
      );
}

class ActiveRidePage extends StatelessWidget {
  const ActiveRidePage({super.key});

  @override
  Widget build(BuildContext context) => RideMapShell(
        processStep: 4,
        showRoute: true,
        showMarker: false,
        // Fit the sheet to its content; only scroll once it reaches this cap.
        fitPanelToContent: true,
        panelMaxHeightFactor: .82,
        panelFooter: AppButton(
          label: 'إنهاء الرحلة التجريبية',
          onPressed: () => Get.toNamed<void>(RideRoutes.review),
        ),
        top: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const RideBackButton(),
            RideStatusPill(
              label: 'الوصول 01:05 م',
              icon: Icons.schedule_rounded,
            ),
          ],
        ),
        panel: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const RidePanelHandle(),
            const RideSectionHeader(
              title: 'أنت في الطريق',
              subtitle: 'متبقٍ 8 دقائق للوصول إلى شركة ارتقاء سوفت.',
            ),
            const SizedBox(height: AppSpacing.md),
            const DriverCard(status: 'الرحلة جارية'),
            const SizedBox(height: AppSpacing.sm),
            TripMetricRow(),
            const SizedBox(height: AppSpacing.md),
            const TripSafetyActions(),
          ],
        ),
      );
}

class RideReviewPage extends GetView<PaymentController> {
  const RideReviewPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        title: 'تقييم الرحلة',
        footer: AppButton(
          label: 'إرسال التقييم',
          onPressed: controller.submitReview,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: AppColors.primary.withValues(alpha: .2),
                  child: Icon(Icons.person_rounded, size: 52),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'كيف كانت رحلتك مع محمد؟',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'تويوتا كامري · ر س د 4821',
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
              AppButton(
                label: 'تخطي الآن',
                variant: AppButtonVariant.text,
                onPressed: () => Get.offAllNamed<void>(RideRoutes.rideThanks),
              ),
            ],
          ),
        ),
      );
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
          action: () => Get.offAllNamed<void>(RideRoutes.homeTransport),
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
        final eta = ride.acceptedOffer.value?.etaMinutes;
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
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person_rounded, color: Colors.black),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      driverName,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text('تحديث حالة الرحلة مباشر',
                        style: TextStyle(color: AppColors.success)),
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
                  ? AppColors.primary
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
                    style:
                        TextStyle(color: message.isMine ? Colors.black : null),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.timeLabel,
                    style: TextStyle(
                      color: message.isMine
                          ? Colors.black54
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
              color: AppColors.primary.withValues(alpha: .2),
            ),
            child: Icon(Icons.person_rounded, size: 82),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'محمد اليمني',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
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
