import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/config/app_environment.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../account/account_routes.dart';
import '../controllers/ride_controller.dart';
import '../controllers/safety_recording_controller.dart';
import '../ride_routes.dart';
import 'ride_common_widgets.dart';

class DriverCard extends StatelessWidget {
  const DriverCard({
    this.showActions = true,
    this.status = 'سيصل خلال 3 دقائق',
    super.key,
  });

  final bool showActions;
  final String status;

  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = Get.find<RideController>();
        final offer = ride.acceptedOffer.value;
        final driverName = offer?.driverName.trim().isNotEmpty == true
            ? offer!.driverName
            : ride.assignedDriverName.value.isNotEmpty
                ? ride.assignedDriverName.value
                : 'السائق المعين';
        final vehicle = offer?.vehicleSummary.trim().isNotEmpty == true
            ? offer!.vehicleSummary
            : 'بيانات المركبة قيد التحميل';
        final rating = offer?.rating ?? 0;
        return AppCard(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withValues(alpha: .2),
                    child: Icon(Icons.person_rounded, size: 34),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          driverName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: AppColors.primaryDark,
                            ),
                            SizedBox(width: 4),
                            Text(rating > 0 ? rating.toStringAsFixed(1) : '—'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        vehicle,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      const Text(''),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: RideStatusPill(
                      label: status,
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                  if (showActions) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    RideIconButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      tooltip: 'محادثة',
                      onPressed: () => Get.toNamed<void>(RideRoutes.chat),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    RideIconButton(
                      icon: Icons.call_outlined,
                      tooltip: 'اتصال',
                      onPressed: () async {
                        final phone = ride.assignedDriverPhone.value;
                        if (phone.isEmpty ||
                            !await launchUrl(Uri(scheme: 'tel', path: phone))) {
                          Get.snackbar(
                            'تعذر الاتصال',
                            'رقم السائق غير متاح حاليًا.',
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      });
}

class RouteSummaryCard extends StatelessWidget {
  const RouteSummaryCard({
    this.from,
    this.to,
    this.compact = false,
    super.key,
  });

  final String? from;
  final String? to;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final draft = Get.isRegistered<RideController>()
        ? Get.find<RideController>().currentDraft.value
        : null;
    final fromLabel = from?.trim().isNotEmpty == true
        ? from!.trim()
        : draft?.pickupAddress.trim().isNotEmpty == true
            ? draft!.pickupAddress.trim()
            : draft?.pickup ?? 'نقطة الانطلاق';
    final toLabel = to?.trim().isNotEmpty == true
        ? to!.trim()
        : draft?.destinationAddressName.trim().isNotEmpty == true
            ? draft!.destinationAddressName.trim()
            : draft?.destinationAddress.trim().isNotEmpty == true
                ? draft!.destinationAddress.trim()
                : draft?.destination ?? 'الوجهة المحددة';
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Icon(Icons.circle, color: AppColors.primaryDark, size: 13),
              Container(
                height: compact ? 31 : 44,
                width: 2,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .18),
              ),
              Icon(
                Icons.location_on_rounded,
                color: AppColors.secondary,
                size: 19,
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('من', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  fromLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: compact ? 10 : 18),
                Text('إلى', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  toLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TripMetricRow extends StatelessWidget {
  const TripMetricRow({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = Get.find<RideController>();
        final draft = ride.currentDraft.value;
        final distanceKm = draft?.routeDistanceMeters != null
            ? draft!.routeDistanceMeters! / 1000
            : ride.routeDistanceKm.value;
        final durationSeconds = draft?.routeDurationSeconds;
        final price = ride.acceptedOffer.value?.price ??
            (ride.offeredPrice.value > 0 ? ride.offeredPrice.value : null);
        return Row(
          children: <Widget>[
            Expanded(
              child: _TripMetric(
                icon: Icons.schedule_rounded,
                value: durationSeconds == null
                    ? '—'
                    : '${(durationSeconds / 60).ceil()} د',
                label: 'المدة',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _TripMetric(
                icon: Icons.route_rounded,
                value: distanceKm > 0
                    ? '${distanceKm.toStringAsFixed(1)} كم'
                    : '—',
                label: 'المسافة',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _TripMetric(
                icon: Icons.payments_outlined,
                value: price == null
                    ? '—'
                    : '${price.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                label: 'التكلفة',
              ),
            ),
          ],
        );
      });
}

class TripSafetyActions extends StatelessWidget {
  const TripSafetyActions({super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: AppButton(
              label: 'مشاركة الرحلة',
              variant: AppButtonVariant.outline,
              size: AppButtonSize.small,
              leading: Icon(Icons.share_outlined, size: 19),
              onPressed: () {},
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton(
              label: 'مساعدة',
              variant: AppButtonVariant.outline,
              size: AppButtonSize.small,
              leading: Icon(Icons.shield_outlined, size: 19),
              onPressed: () {},
            ),
          ),
        ],
      );
}

class TripEmergencyActions extends StatelessWidget {
  const TripEmergencyActions({
    required this.onShareTrip,
    required this.onCancelRide,
    super.key,
  });

  final VoidCallback onShareTrip;
  final VoidCallback onCancelRide;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          Expanded(
            child: _EmergencyAction(
              icon: Icons.health_and_safety_outlined,
              label: 'safety'.tr,
              onTap: () => _showSafetySheet(context, onShareTrip),
            ),
          ),
          Expanded(
            child: _EmergencyAction(
              icon: Icons.ios_share_rounded,
              label: 'share_my_trip'.tr,
              onTap: onShareTrip,
            ),
          ),
          Expanded(
            child: _EmergencyAction(
              icon: Icons.cancel_outlined,
              label: 'confirm_cancel_ride'.tr,
              isUrgent: true,
              onTap: onCancelRide,
            ),
          ),
        ],
      );

  void _showSafetySheet(BuildContext context, VoidCallback onShareTrip) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Get.bottomSheet<void>(
      FractionallySizedBox(
        heightFactor: .92,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                top: BorderSide(color: colors.primary.withValues(alpha: .38)),
              ),
            ),
            child: _SafetySheetContent(
              onShareTrip: onShareTrip,
              onCallEmergency: _callEmergency,
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  static final Uri _emergencyNumber = Uri(scheme: 'tel', path: '122');

  Future<void> _callEmergency() async {
    if (!await launchUrl(_emergencyNumber)) {
      Get.snackbar('call_122'.tr, 'call_failed'.tr);
    }
  }
}

class _SafetySheetContent extends StatefulWidget {
  const _SafetySheetContent({
    required this.onShareTrip,
    required this.onCallEmergency,
  });

  final VoidCallback onShareTrip;
  final VoidCallback onCallEmergency;

  @override
  State<_SafetySheetContent> createState() => _SafetySheetContentState();
}

class _SafetySheetContentState extends State<_SafetySheetContent> {
  final SafetyRecordingController _recording =
      Get.find<SafetyRecordingController>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Obx(() => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.health_and_safety_outlined,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'safety_tools'.tr,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'safety_tools_hint'.tr,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 6,
                childAspectRatio: 1.15,
                children: <Widget>[
                  _SafetySheetAction(
                    icon: Icons.ios_share_rounded,
                    label: 'share_my_trip'.tr,
                    onTap: () {
                      Get.back<void>();
                      widget.onShareTrip();
                    },
                  ),
                  _SafetySheetAction(
                    icon: Icons.phone_in_talk_rounded,
                    label: 'call_122'.tr,
                    isDanger: true,
                    onTap: widget.onCallEmergency,
                  ),
                  _SafetySheetAction(
                    icon: _recording.isRecording.value
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                    label: _recording.isRecording.value
                        ? 'stop_audio_recording'.tr
                        : 'start_audio_recording'.tr,
                    isDanger: _recording.isRecording.value,
                    onTap: () {
                      if (!_recording.isWorking.value) {
                        unawaited(_toggleRecording());
                      }
                    },
                  ),
                  _SafetySheetAction(
                    icon: Icons.contacts_outlined,
                    label: 'emergency_contacts'.tr,
                    onTap: () => Get.snackbar(
                      'emergency_contacts'.tr,
                      'emergency_contacts_hint'.tr,
                    ),
                  ),
                  _SafetySheetAction(
                    icon: Icons.support_agent_rounded,
                    label: 'support'.tr,
                    onTap: () {
                      Get.back<void>();
                      Get.toNamed<void>(AccountRoutes.help);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'how_we_protect_you'.tr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _SafetyInfoCard(
                      icon: Icons.shield_outlined,
                      title: 'proactive_safety_support'.tr,
                      hint: 'proactive_safety_support_hint'.tr,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SafetyInfoCard(
                      icon: Icons.verified_user_outlined,
                      title: 'driver_verification'.tr,
                      hint: 'driver_verification_hint'.tr,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SafetyInfoCard(
                icon: Icons.share_location_outlined,
                title: 'share_my_trip'.tr,
                hint: 'trip_sharing_hint'.tr,
              ),
            ],
          ),
        ));
  }

  Future<void> _toggleRecording() async {
    if (_recording.isRecording.value) {
      await _recording.stop();
      if (_recording.error.value.isEmpty) {
        Get.snackbar(
            'stop_audio_recording'.tr, 'تم حفظ تسجيل السلامة على الخادم.');
      } else {
        Get.snackbar('stop_audio_recording'.tr, _recording.error.value);
      }
      return;
    }

    final consent = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('تسجيل السلامة'),
        content: const Text(
          'سيُسجل صوت هذه الرحلة ويُرسل إلى خادم يمن درايف أثناء التسجيل. '
          'تستطيع إيقافه في أي وقت.',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Get.back<bool>(result: false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Get.back<bool>(result: true),
              child: const Text('أوافق وأبدأ')),
        ],
      ),
    );
    if (consent != true) return;
    final started = await _recording.start();
    Get.snackbar(
      started ? 'start_audio_recording'.tr : 'تعذر بدء التسجيل',
      started
          ? 'تسجيل السلامة نشط ومرفوع إلى الخادم أثناء الرحلة.'
          : _recording.error.value,
    );
  }
}

class _SafetySheetAction extends StatelessWidget {
  const _SafetySheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
  @override
  Widget build(BuildContext context) {
    final color = isDanger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: .13),
                border: Border.all(color: color.withValues(alpha: .32)),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyInfoCard extends StatelessWidget {
  const _SafetyInfoCard({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;
  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _EmergencyAction extends StatelessWidget {
  const _EmergencyAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isUrgent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = isUrgent ? colors.error : colors.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: color.withValues(alpha: .14),
          shape: CircleBorder(
            side: BorderSide(color: color.withValues(alpha: .35)),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: color, size: 23),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
        ),
      ],
    );
  }
}

class PriceSummary extends StatelessWidget {
  const PriceSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final ride = Get.find<RideController>();
    final fare = ride.acceptedOffer.value?.price ?? ride.offeredPrice.value;
    final fee = ride.quote.value?.serviceFee ?? 0;
    final total = fare + fee;
    String money(double value) =>
        '${value.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}';
    return AppCard(
      child: Column(
        children: <Widget>[
          _PriceRow(
            label: 'أجرة الرحلة',
            value: money(fare),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PriceRow(
            label: 'رسوم الخدمة',
            value: money(fee),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(height: 1),
          ),
          _PriceRow(
            label: 'الإجمالي',
            value: money(total),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _TripMetric extends StatelessWidget {
  const _TripMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: <Widget>[
            Icon(icon, color: AppColors.primaryDark, size: 22),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.value, this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      );
}
