import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/responsive/app_responsive.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../controllers/ride_controller.dart';
import '../ride_routes.dart';
import '../widgets/ride_common_widgets.dart';
import '../widgets/ride_map_shell.dart';
import '../widgets/ride_trip_widgets.dart';
import '../widgets/ride_vehicle_widgets.dart';

class TransportSelectionPage extends GetView<RideController> {
  const TransportSelectionPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        title: 'اختر وسيلة النقل',
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const RideSectionHeader(
                title: 'كيف تفضّل الوصول؟',
                subtitle: 'اختر الوسيلة المناسبة لعدد الركاب ووقت وصولك.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Obx(
                () {
                  final vehicles = controller.vehicles;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (controller.isCatalogLoading.value)
                        const Padding(
                          padding: EdgeInsets.only(bottom: AppSpacing.sm),
                          child: LinearProgressIndicator(),
                        ),
                      if (controller.catalogError.value.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Text(
                            controller.catalogError.value,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (vehicles.isEmpty &&
                          !controller.isCatalogLoading.value)
                        const AppCard(
                          child: Text(
                            'لا توجد وسائل متاحة لهذا النوع حاليًا.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 620 ? 4 : 2;
                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: columns,
                              mainAxisSpacing: AppSpacing.sm,
                              crossAxisSpacing: AppSpacing.sm,
                              childAspectRatio: columns == 4 ? .86 : .82,
                              children: vehicles
                                  .map(
                                    (vehicle) => VehiclePreviewCard(
                                      vehicle: vehicle,
                                      onTap: () => controller
                                          .selectCatalogVehicle(vehicle),
                                    ),
                                  )
                                  .toList(growable: false),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
}

class VehicleCatalogPage extends GetView<RideController> {
  const VehicleCatalogPage({super.key});

  @override
  Widget build(BuildContext context) => RideMapShell(
        processStep: 2,
        showRoute: true,
        showMarker: false,
        panelMaxHeightFactor: .55,
        panelFooter: AppButton(
          label: 'عرض جميع السيارات',
          variant: AppButtonVariant.outline,
          onPressed: () => Get.toNamed<void>(RideRoutes.vehicleList),
        ),
        top: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const RideBackButton(),
            RideStatusPill(
              label: controller.selectedVehicle.value?.name ?? 'الخدمة',
              icon: Icons.miscellaneous_services_outlined,
            ),
          ],
        ),
        panel: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const RidePanelHandle(),
              RideSectionHeader(
                title: 'مركبات قريبة منك',
                subtitle: 'الأسعار تقديرية وقد تتغير بحسب الازدحام.',
                trailing: TextButton(
                  onPressed: () => Get.toNamed<void>(RideRoutes.vehicleList),
                  child: const Text('عرض القائمة'),
                ),
              ),
              if (controller.isCatalogLoading.value)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                ),
              if (controller.catalogError.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    controller.catalogError.value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.vehicles.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final vehicle = controller.vehicles[index];
                    return SizedBox(
                      width: ResponsiveContext(
                        context,
                      ).responsiveValue(phone: 300, tablet: 330),
                      child: VehiclePreviewCard(
                        vehicle: vehicle,
                        onTap: () => controller.selectVehicle(vehicle),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class VehicleListPage extends GetView<RideController> {
  const VehicleListPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        title: 'السيارات المتاحة',
        body: Obx(
          () => ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            children: <Widget>[
              if (controller.isCatalogLoading.value)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                ),
              if (controller.catalogError.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    controller.catalogError.value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ...controller.vehicles.map(
                (vehicle) => VehicleBookingTile(vehicle: vehicle),
              ),
            ],
          ),
        ),
      );
}

class VehicleDetailsPage extends GetView<RideController> {
  const VehicleDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vehicle =
        controller.selectedVehicle.value ?? controller.vehicles.first;
    return RidePageFrame(
      title: 'تفاصيل المركبة',
      footer: Row(
        children: <Widget>[
          Expanded(
            child: AppButton(
              label: 'احجز لاحقاً',
              variant: AppButtonVariant.outline,
              onPressed: () => controller.requestRide(later: true),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton(
              label: 'اركب الآن',
              onPressed: controller.requestRide,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            VehicleHero(vehicle: vehicle),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        vehicle.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(vehicle.description),
                    ],
                  ),
                ),
                RideStatusPill(
                  label:
                      '${vehicle.price.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency}',
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                VehicleFeature(
                  icon: Icons.star_rounded,
                  label: 'التقييم',
                  value: vehicle.rating.toStringAsFixed(1),
                ),
                const SizedBox(width: AppSpacing.sm),
                VehicleFeature(
                  icon: Icons.person_outline_rounded,
                  label: 'المقاعد',
                  value: '${vehicle.seats}',
                ),
                const SizedBox(width: AppSpacing.sm),
                VehicleFeature(
                  icon: Icons.schedule_rounded,
                  label: 'الوصول',
                  value: '${vehicle.arrivalMinutes} د',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const RouteSummaryCard(),
          ],
        ),
      ),
    );
  }
}

class RideRequestPage extends GetView<RideController> {
  const RideRequestPage({super.key});

  @override
  Widget build(BuildContext context) => RideMapShell(
        processStep: 3,
        showRoute: true,
        showMarker: false,
        panelMaxHeightFactor: .49,
        top: const Align(
          alignment: AlignmentDirectional.topStart,
          child: RideBackButton(),
        ),
        panelFooter: AppButton(
          label: 'متابعة الطلب التجريبي',
          onPressed: controller.driverFound,
        ),
        panel: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const RidePanelHandle(),
            Center(
              child: SizedBox(
                width: 66,
                height: 66,
                child: CircularProgressIndicator(
                  strokeWidth: 6,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'نبحث عن أقرب سائق',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'عادةً يستغرق العثور على سائق أقل من دقيقة.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            const RouteSummaryCard(compact: true),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'إلغاء الطلب',
              variant: AppButtonVariant.text,
              onPressed: () => Get.toNamed<void>(RideRoutes.rideCancel),
            ),
          ],
        ),
      );
}

class RideCancelPage extends GetView<RideController> {
  const RideCancelPage({super.key});

  static const List<String> _reasons = <String>[
    'انتظرت وقتاً طويلاً',
    'غيّرت وجهتي',
    'حجزت الرحلة بالخطأ',
    'لم أتمكن من التواصل مع السائق',
    'سبب آخر',
  ];

  @override
  Widget build(BuildContext context) => RidePageFrame(
        title: 'إلغاء الرحلة',
        footer: Obx(
          () => AppButton(
            label: 'تأكيد الإلغاء',
            variant: AppButtonVariant.danger,
            isDisabled: controller.cancellationReason.value.isEmpty,
            onPressed: () => controller.cancelRide(
              controller.cancellationReason.value,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const RideSectionHeader(
                title: 'لماذا تريد الإلغاء؟',
                subtitle:
                    'يساعدنا اختيار السبب في تحسين تجربة الرحلات القادمة.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Obx(
                () => Column(
                  children: _reasons
                      .map(
                        (reason) => AppCard(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          onTap: () =>
                              controller.cancellationReason.value = reason,
                          borderColor:
                              controller.cancellationReason.value == reason
                                  ? AppColors.primary
                                  : null,
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  reason,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Radio<String>(
                                value: reason,
                                groupValue: controller.cancellationReason.value,
                                activeColor: AppColors.primaryDark,
                                onChanged: (value) => controller
                                    .cancellationReason.value = value ?? '',
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              AppButton(
                label: 'العودة إلى الطلب',
                variant: AppButtonVariant.text,
                onPressed: () => Get.back<void>(),
              ),
            ],
          ),
        ),
      );
}

class RequestThanksPage extends StatelessWidget {
  const RequestThanksPage({super.key});

  @override
  Widget build(BuildContext context) => RidePageFrame(
        showBack: false,
        body: RideSuccessView(
          icon: Icons.favorite_rounded,
          title: 'شكراً لإخبارنا',
          message: 'تم إلغاء الطلب بنجاح، ولن تُخصم منك أي رسوم لهذه الرحلة.',
          actionLabel: 'العودة إلى الرئيسية',
          action: () => Get.offAllNamed<void>(RideRoutes.homeTransport),
        ),
      );
}
