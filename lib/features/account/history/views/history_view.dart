import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/config/app_environment.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_states.dart';
import '../../account_routes.dart';
import '../../models/account_models.dart';
import '../../widgets/account_widgets.dart';
import '../../../ride/controllers/ride_controller.dart';
import '../controllers/history_controller.dart';

class HistoryPage extends GetView<HistoryController> {
  const HistoryPage({required this.status, super.key});

  final RideHistoryStatus status;

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'سجل الرحلات',
        scrollable: false,
        child: Column(
          children: <Widget>[
            _HistoryTabs(status: status),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value) return const AppLoading();
                final rides = controller.byStatus(status);
                if (rides.isEmpty) {
                  return const AppEmptyState(
                    title: 'لا توجد رحلات',
                    message: 'ستظهر رحلاتك هنا عند توفرها.',
                    icon: Icons.route_outlined,
                  );
                }
                return RefreshIndicator(
                  onRefresh: controller.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    itemCount: rides.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) =>
                        _HistoryRideCard(ride: rides[index]),
                  ),
                );
              }),
            ),
          ],
        ),
      );
}

class _HistoryTabs extends StatelessWidget {
  const _HistoryTabs({required this.status});

  final RideHistoryStatus status;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: AppButton(
              label: 'القادمة',
              size: AppButtonSize.small,
              variant: status == RideHistoryStatus.upcoming
                  ? AppButtonVariant.primary
                  : AppButtonVariant.outline,
              onPressed: () => _open(
                AccountRoutes.historyUpcoming,
                RideHistoryStatus.upcoming,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AppButton(
              label: 'المكتملة',
              size: AppButtonSize.small,
              variant: status == RideHistoryStatus.completed
                  ? AppButtonVariant.primary
                  : AppButtonVariant.outline,
              onPressed: () => _open(
                AccountRoutes.historyCompleted,
                RideHistoryStatus.completed,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AppButton(
              label: 'الملغاة',
              size: AppButtonSize.small,
              variant: status == RideHistoryStatus.cancelled
                  ? AppButtonVariant.primary
                  : AppButtonVariant.outline,
              onPressed: () => _open(
                AccountRoutes.historyCancelled,
                RideHistoryStatus.cancelled,
              ),
            ),
          ),
        ],
      );

  void _open(String route, RideHistoryStatus next) {
    if (status != next) Get.offNamed<void>(route);
  }
}

class _HistoryRideCard extends StatelessWidget {
  const _HistoryRideCard({required this.ride});

  final RideHistoryItem ride;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (ride.status) {
      RideHistoryStatus.upcoming => AppColors.primaryDark,
      RideHistoryStatus.completed => AppColors.success,
      RideHistoryStatus.cancelled => AppColors.error,
    };
    final statusLabel = switch (ride.status) {
      RideHistoryStatus.upcoming => 'قادمة',
      RideHistoryStatus.completed => 'مكتملة',
      RideHistoryStatus.cancelled => 'ملغاة',
    };
    return AppCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${ride.amount.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency} ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          AccountRouteLine(pickup: ride.pickup, destination: ride.destination),
          const Divider(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              const Icon(Icons.calendar_month_outlined, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(_rideDate(ride.date))),
              if (ride.status == RideHistoryStatus.completed)
                TextButton(
                  onPressed: () => Get.snackbar(
                    'تفاصيل الرحلة',
                    'يمكن ربطها بفاتورة الرحلة من الخادم.',
                  ),
                  child: const Text('الفاتورة'),
                ),
            ],
          ),
          if (ride.status == RideHistoryStatus.upcoming)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: AppButton(
                label: 'استئناف الرحلة',
                size: AppButtonSize.small,
                variant: AppButtonVariant.outline,
                onPressed: () async {
                  try {
                    await Get.find<RideController>().resumeOpenRide(ride.id);
                  } catch (_) {
                    Get.snackbar(
                      'تعذر استئناف الرحلة',
                      'حدّث سجل الرحلات وتحقق من حالة الطلب ثم أعد المحاولة.',
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _rideDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} - ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
