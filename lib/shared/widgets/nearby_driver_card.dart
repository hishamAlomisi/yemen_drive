import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/cache/persistent_network_image.dart';
import '../../features/ride/models/ride_models.dart';

class NearbyDriverCard extends StatelessWidget {
  const NearbyDriverCard({
    required this.driver,
    required this.pointerX,
    required this.onClose,
    super.key,
  });

  final NearbyDriver driver;
  final double pointerX;
  final VoidCallback onClose;

  String get _vehicleTypeKey => switch (driver.vehicleType) {
        RideVehicleType.car => 'vehicle_car',
        RideVehicleType.taxi => 'vehicle_taxi',
        RideVehicleType.bike => 'vehicle_bike',
        RideVehicleType.cycle => 'vehicle_cycle',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final surface = colors.surface.withValues(alpha: .96);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          bottom: 10,
          child: Material(
            color: surface,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: .28),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colors.primary.withValues(alpha: .42),
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _DriverPhoto(driver: driver),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                driver.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.star_rounded,
                                    size: 17,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    driver.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      '${driver.completedTrips} ${'completed_trips'.tr}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: onClose,
                          tooltip: 'close_driver_details'.tr,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 19),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    const SizedBox(height: 9),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _DriverDetail(
                            icon: Icons.directions_car_filled_rounded,
                            label: 'vehicle_model'.tr,
                            value: driver.vehicleModel.isEmpty
                                ? _vehicleTypeKey.tr
                                : '${_vehicleTypeKey.tr} · ${driver.vehicleModel}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DriverDetail(
                            icon: Icons.pin_outlined,
                            label: 'plate_number'.tr,
                            value: driver.plateNumber,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: pointerX - 8,
          bottom: 3,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  right: BorderSide(
                    color: colors.primary.withValues(alpha: .42),
                  ),
                  bottom: BorderSide(
                    color: colors.primary.withValues(alpha: .42),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverPhoto extends StatelessWidget {
  const _DriverPhoto({required this.driver});

  final NearbyDriver driver;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: driver.photoUrl.isEmpty
              ? Image.asset(
                  'assets/images/branding/brand_logo.webp',
                  cacheWidth:
                      (52 * MediaQuery.devicePixelRatioOf(context)).round(),
                  fit: BoxFit.contain,
                )
              : PersistentNetworkImage(
                  driver.photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.person_rounded,
                  ),
                ),
        ),
      );
}

class _DriverDetail extends StatelessWidget {
  const _DriverDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            size: 17,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 9,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
