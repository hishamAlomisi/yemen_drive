import 'package:flutter/material.dart';

import '../../../../core/cache/persistent_network_image.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../models/service_kind_models.dart';

class BookingServiceKindButton extends StatelessWidget {
  const BookingServiceKindButton({
    required this.service,
    this.onTap,
    super.key,
  });

  final RideHomeService? service;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: colors.primary.withValues(alpha: .08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.primary.withValues(alpha: .24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: <Widget>[
                BookingServiceImage(service: service, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'نوع الرحلة',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                      Text(
                        service?.name ?? 'اختر نوع الرحلة',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single, bounded row keeps the home map visible for any service count.
class BookingServiceKindsStrip extends StatelessWidget {
  const BookingServiceKindsStrip({
    required this.services,
    required this.selectedId,
    this.onSelected,
    super.key,
  });

  final List<RideHomeService> services;
  final int? selectedId;
  final ValueChanged<RideHomeService>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);
    return SizedBox(
      height: 114 * textScale,
      child: ListView.separated(
        key: const ValueKey('home-service-kinds'),
        scrollDirection: Axis.horizontal,
        itemCount: services.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final service = services[index];
          final selected = service.id == selectedId;
          return Semantics(
            selected: selected,
            button: true,
            child: AnimatedContainer(
              key: ValueKey('home-kind-${service.id}'),
              duration: const Duration(milliseconds: 180),
              width: 110 * textScale,
              decoration: BoxDecoration(
                color: selected
                    ? colors.primaryContainer
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: selected
                      ? colors.primary
                      : colors.outlineVariant.withValues(alpha: .45),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(17),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onSelected == null ? null : () => onSelected!(service),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Center(
                                child: BookingServiceImage(
                                  service: service,
                                  size: 58,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              service.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: selected
                                        ? colors.onPrimaryContainer
                                        : colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: colors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class BookingServiceKindsSheet extends StatelessWidget {
  const BookingServiceKindsSheet({
    required this.services,
    required this.selectedId,
    required this.onSelected,
    required this.onClose,
    this.enabled = true,
    this.isLoading = false,
    this.error = '',
    this.onRetry,
    super.key,
  });

  final List<RideHomeService> services;
  final int? selectedId;
  final ValueChanged<RideHomeService> onSelected;
  final VoidCallback onClose;
  final bool enabled;
  final bool isLoading;
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'نوع الرحلة',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'اختر الخدمة المناسبة لمشوارك',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (isLoading) const LinearProgressIndicator(),
              if (error.isNotEmpty || (!isLoading && services.isEmpty))
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        error.isNotEmpty
                            ? error
                            : 'لا توجد أنواع رحلات متاحة حالياً',
                      ),
                      if (onRetry != null)
                        TextButton.icon(
                          onPressed: isLoading ? null : onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                    ],
                  ),
                ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: services.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final service = services[index];
                    return BookingServiceKindCard(
                      service: service,
                      selected: service.id != null && service.id == selectedId,
                      onTap: enabled ? () => onSelected(service) : null,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: AppButton(label: 'تم', onPressed: onClose),
              ),
            ],
          ),
        ),
      );
}

class BookingServiceKindCard extends StatelessWidget {
  const BookingServiceKindCard({
    required this.service,
    required this.selected,
    this.onTap,
    super.key,
  });

  final RideHomeService service;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final description = service.description?.trim() ?? '';
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: ShapeDecoration(
          color:
              selected ? colors.primaryContainer : colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: .6),
              width: selected ? 1.5 : 1,
            ),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BookingServiceImage(service: service, size: 72),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          service.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (description.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                        if (service.isDefault) ...<Widget>[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface.withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'النوع الافتراضي',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected ? colors.onSurface : colors.surface,
                      shape: BoxShape.circle,
                      border: selected
                          ? null
                          : Border.all(color: colors.outlineVariant),
                    ),
                    child: selected
                        ? Icon(Icons.check, color: colors.surface, size: 17)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingServiceImage extends StatelessWidget {
  const BookingServiceImage({
    required this.service,
    required this.size,
    super.key,
  });

  final RideHomeService? service;
  final double size;

  @override
  Widget build(BuildContext context) {
    final source = service?.imageUrl?.trim() ?? '';
    final colors = Theme.of(context).colorScheme;
    final fallback = Icon(
      service?.code.toLowerCase() == 'delivery'
          ? Icons.local_shipping_outlined
          : Icons.local_taxi_outlined,
      size: size * .52,
      color: colors.onSurfaceVariant,
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .08),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(size * .22),
      ),
      clipBehavior: Clip.antiAlias,
      child: source.isEmpty
          ? fallback
          : source.startsWith('http')
              ? PersistentNetworkImage(
                  source,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                )
              : Image.asset(
                  source,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                ),
    );
  }
}
