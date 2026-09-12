import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/config/app_environment.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';

extension RideVehicleTypePresentation on RideVehicleType {
  String get arabicLabel => switch (this) {
        RideVehicleType.car => 'سيارة',
        RideVehicleType.bike => 'دراجة نارية',
        RideVehicleType.cycle => 'دراجة هوائية',
        RideVehicleType.taxi => 'تاكسي',
      };

  String get arabicSubtitle => switch (this) {
        RideVehicleType.car => 'مريحة حتى 4 ركاب',
        RideVehicleType.bike => 'الأسرع للرحلات القصيرة',
        RideVehicleType.cycle => 'اقتصادية وصديقة للبيئة',
        RideVehicleType.taxi => 'تاكسي مرخّص قريب منك',
      };

  IconData get icon => switch (this) {
        RideVehicleType.car => Icons.directions_car_filled_rounded,
        RideVehicleType.bike => Icons.two_wheeler_rounded,
        RideVehicleType.cycle => Icons.pedal_bike_rounded,
        RideVehicleType.taxi => Icons.local_taxi_rounded,
      };

  String get imageAsset => switch (this) {
        RideVehicleType.car => 'assets/images/vehicles/car.jpg',
        RideVehicleType.bike => 'assets/images/vehicles/delivery_scooter.jpg',
        RideVehicleType.cycle => 'assets/images/vehicles/delivery_bicycle.jpg',
        RideVehicleType.taxi => 'assets/images/vehicles/taxi.png',
      };

  String get localizedLabel => switch (this) {
        RideVehicleType.car => 'vehicle_car'.tr,
        RideVehicleType.bike => 'vehicle_bike'.tr,
        RideVehicleType.cycle => 'vehicle_cycle'.tr,
        RideVehicleType.taxi => 'vehicle_taxi'.tr,
      };

  String get localizedDescription => switch (this) {
        RideVehicleType.car => 'transport_car_description'.tr,
        RideVehicleType.bike => 'transport_bike_description'.tr,
        RideVehicleType.cycle => 'transport_cycle_description'.tr,
        RideVehicleType.taxi => 'transport_taxi_description'.tr,
      };
}

class TransportModeListCard extends StatelessWidget {
  const TransportModeListCard({
    required this.type,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final RideVehicleType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: selected
            ? colors.primary.withValues(alpha: .10)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colors.primary
              : colors.onSurface.withValues(alpha: .10),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: <Widget>[
                Container(
                  width: 78,
                  height: 66,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: .55,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Image.asset(
                    type.imageAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => Icon(
                      type.icon,
                      size: 34,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        type.localizedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type.localizedDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? colors.primary : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? colors.primary
                          : colors.onSurface.withValues(alpha: .28),
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colors.onPrimary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Catalog-backed transport card. Unlike [TransportModeListCard], its label,
/// description, image and metadata are supplied by the API catalog.
class CatalogTransportListCard extends StatelessWidget {
  const CatalogTransportListCard({
    required this.vehicle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final RideVehicle vehicle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = vehicle.imageAsset;
    final isRemote = source != null &&
        (source.startsWith('http://') || source.startsWith('https://'));
    final image = source == null || source.isEmpty
        ? null
        : (isRemote
            ? Image.network(source, fit: BoxFit.contain)
            : Image.asset(source, fit: BoxFit.contain));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: selected
            ? colors.primary.withValues(alpha: .10)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colors.primary
              : colors.onSurface.withValues(alpha: .10),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: <Widget>[
                Container(
                  width: 78,
                  height: 66,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: image == null
                      ? Icon(vehicle.type.icon, size: 34, color: colors.primary)
                      : (isRemote
                          ? Image.network(
                              source,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                vehicle.type.icon,
                                size: 34,
                                color: colors.primary,
                              ),
                            )
                          : Image.asset(
                              source!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                vehicle.type.icon,
                                size: 34,
                                color: colors.primary,
                              ),
                            )),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        vehicle.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vehicle.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? colors.primary : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? colors.primary
                          : colors.onSurface.withValues(alpha: .28),
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded,
                          size: 16, color: colors.onPrimary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TransportModeCard extends StatelessWidget {
  const TransportModeCard({required this.type, required this.onTap, super.key});

  final RideVehicleType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: AspectRatio(
          aspectRatio: 1.08,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 104,
                height: 104,
                child: Image.asset(
                  type.imageAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    type.icon,
                    size: 42,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                type.arabicLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                type.arabicSubtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class VehiclePreviewCard extends StatelessWidget {
  const VehiclePreviewCard({
    required this.vehicle,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final RideVehicle vehicle;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        borderColor: vehicle.isRecommended ? AppColors.primary : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _VehicleIllustration(vehicle: vehicle, compact: compact),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (vehicle.isRecommended)
                        Padding(
                          padding: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'موصى به',
                            style: TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Text(
                        vehicle.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'يصل خلال ${vehicle.arrivalMinutes} دقائق',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${vehicle.price.toStringAsFixed(0)} ${AppEnvironment.defaultCurrency} ',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            if (!compact) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                vehicle.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  _VehicleMeta(
                    icon: Icons.star_rounded,
                    label: vehicle.rating.toStringAsFixed(1),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _VehicleMeta(
                    icon: Icons.person_outline_rounded,
                    label: '${vehicle.seats} مقاعد',
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

class VehicleBookingTile extends GetView<RideController> {
  const VehicleBookingTile({required this.vehicle, super.key});

  final RideVehicle vehicle;

  @override
  Widget build(BuildContext context) => AppCard(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        onTap: () => controller.selectVehicle(vehicle),
        child: Column(
          children: <Widget>[
            VehiclePreviewCard(
              vehicle: vehicle,
              compact: true,
              onTap: () => controller.selectVehicle(vehicle),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    label: 'احجز لاحقاً',
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.outline,
                    onPressed: () {
                      controller.selectedVehicle.value = vehicle;
                      controller.requestRide(later: true);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'اركب الآن',
                    size: AppButtonSize.small,
                    onPressed: () {
                      controller.selectedVehicle.value = vehicle;
                      controller.requestRide();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class VehicleFeature extends StatelessWidget {
  const VehicleFeature({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: <Widget>[
                Icon(icon, color: AppColors.primaryDark),
                const SizedBox(height: 6),
                Text(value, style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}

class VehicleHero extends StatelessWidget {
  const VehicleHero({required this.vehicle, super.key});

  final RideVehicle vehicle;

  @override
  Widget build(BuildContext context) => Container(
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: <Color>[
              AppColors.primary.withValues(alpha: .34),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned(
              bottom: 25,
              child: Container(
                width: 230,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black26, blurRadius: 20),
                  ],
                ),
              ),
            ),
            Icon(vehicle.type.icon, size: 126, color: AppColors.primaryDark),
          ],
        ),
      );
}

class _VehicleIllustration extends StatelessWidget {
  const _VehicleIllustration({required this.vehicle, required this.compact});

  final RideVehicle vehicle;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        width: compact ? 56 : 68,
        height: compact ? 48 : 58,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        alignment: Alignment.center,
        child: _VehicleImage(
          source: vehicle.imageAsset ?? vehicle.type.imageAsset,
          fallback: Icon(
            vehicle.type.icon,
            size: compact ? 32 : 39,
            color: AppColors.primaryDark,
          ),
        ),
      );
}

class _VehicleImage extends StatelessWidget {
  const _VehicleImage({required this.source, required this.fallback});

  final String source;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final isRemote =
        source.startsWith('http://') || source.startsWith('https://');
    final image = isRemote
        ? Image.network(
            source,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => fallback,
          )
        : Image.asset(
            source,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => fallback,
          );
    return image;
  }
}

class _VehicleMeta extends StatelessWidget {
  const _VehicleMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 17, color: AppColors.primaryDark),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
