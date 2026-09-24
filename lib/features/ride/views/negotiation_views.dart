import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../ride_routes.dart';
import '../widgets/ride_common_widgets.dart';
import '../widgets/ride_map_shell.dart';
import '../widgets/ride_trip_widgets.dart';

class NegotiationQuotePage extends StatefulWidget {
  const NegotiationQuotePage({super.key});

  @override
  State<NegotiationQuotePage> createState() => _NegotiationQuotePageState();
}

class _NegotiationQuotePageState extends State<NegotiationQuotePage> {
  final RideController controller = Get.find<RideController>();
  Worker? _exhaustedWorker;

  @override
  void initState() {
    super.initState();
    _exhaustedWorker = ever<bool>(controller.offersExhausted, (exhausted) {
      if (exhausted && Get.currentRoute == RideRoutes.negotiationQuote) {
        controller.acknowledgeOffersExhausted();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showOffersExhaustedDialog(),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => controller.resumePendingRequestIfNeeded(),
    );
  }

  Future<void> _showOffersExhaustedDialog() => Get.dialog<void>(
        _OffersDecisionDialog(
          onRetry: () {
            Get.back<void>();
            controller.retryDriverSearch();
          },
          onCancel: () {
            Get.back<void>();
            controller.cancelDriverSearch();
          },
        ),
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .48),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) controller.cancelPendingQuote();
        },
        child: Obx(() {
          final quote = controller.quote.value;
          final quoteError = controller.quoteError.value;
          return RideMapShell(
            processStep: controller.driverOffers.isEmpty ? 3 : null,
            showRoute: true,
            showMarker: false,
            showPassengerSearchRadar: controller.isSearchingForDriver.value,
            fitPanelToContent: true,
            foregroundOverlay: const _FloatingDriverOffers(),
            panelFooter: _NegotiationSearchFooter(
              searching: controller.isSearchingForDriver.value,
              offersCount: controller.receivedOffersCount.value,
              recipients: controller.requestRecipients.toList(growable: false),
              canSend: quote != null,
              onSend: controller.requestRide,
              onCancel: controller.cancelDriverSearch,
            ),
            top: const Align(
              alignment: AlignmentDirectional.topStart,
              child: RideBackButton(),
            ),
            panel: quote == null && quoteError.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : quote == null
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.receipt_long_outlined, size: 44),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              quoteError,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            AppButton(
                              label: 'العودة لاختيار الخدمة',
                              variant: AppButtonVariant.outline,
                              onPressed: () {
                                controller.cancelPendingQuote();
                                Get.back<void>();
                              },
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const RidePanelHandle(),
                          RideSectionHeader(
                            title: 'suggest_trip_price'.tr,
                            subtitle: 'driver_offer_hint'.tr,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: <Widget>[
                              IconButton.filledTonal(
                                onPressed: controller.isSearchingForDriver.value
                                    ? null
                                    : controller.decreasePrice,
                                icon: const Icon(Icons.remove),
                                tooltip: 'decrease_price'.tr,
                              ),
                              Expanded(
                                child: Column(
                                  children: <Widget>[
                                    Text(
                                      '${controller.offeredPrice.value.toStringAsFixed(0)} ${quote.currency}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    Text(
                                      'الحد المتاح ${quote.minPrice.toStringAsFixed(0)} - ${quote.maxPrice.toStringAsFixed(0)} ${quote.currency}',
                                    ),
                                  ],
                                ),
                              ),
                              IconButton.filled(
                                onPressed: controller.isSearchingForDriver.value
                                    ? null
                                    : controller.increasePrice,
                                icon: const Icon(Icons.add),
                                tooltip: 'increase_price'.tr,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          RouteSummaryCard(compact: true),
                        ],
                      ),
          );
        }),
      );

  @override
  void dispose() {
    _exhaustedWorker?.dispose();
    super.dispose();
  }
}

class _OffersDecisionDialog extends StatelessWidget {
  const _OffersDecisionDialog({
    required this.onRetry,
    required this.onCancel,
  });

  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surface = colors.surface.withValues(alpha: isDark ? .90 : .94);
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.primary.withValues(alpha: .42),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? .38 : .18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: .34),
                            ),
                          ),
                          child: Icon(
                            Icons.manage_search_rounded,
                            color: colors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'still_want_ride'.tr,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'all_offers_expired'.tr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      color: colors.onSurface.withValues(alpha: .09),
                    ),
                    const SizedBox(height: 14),
                    AppButton(
                      label: 'search_driver_again'.tr,
                      size: AppButtonSize.medium,
                      leading: const Icon(Icons.refresh_rounded, size: 19),
                      onPressed: onRetry,
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: 'cancel_ride'.tr,
                      size: AppButtonSize.small,
                      variant: AppButtonVariant.text,
                      leading: const Icon(Icons.close_rounded, size: 18),
                      onPressed: onCancel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NegotiationSearchFooter extends StatelessWidget {
  const _NegotiationSearchFooter({
    required this.searching,
    required this.offersCount,
    required this.recipients,
    required this.canSend,
    required this.onSend,
    required this.onCancel,
  });

  final bool searching;
  final int offersCount;
  final List<NearbyDriver> recipients;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (!searching) {
      return AppButton(
        label: 'send_request_to_drivers'.tr,
        isDisabled: !canSend,
        onPressed: onSend,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colors.onSurface.withValues(alpha: .10),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: .07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'waiting_driver_offers'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'offers_received_count'.trParams(<String, String>{
                    'count': '$offersCount',
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (recipients.isNotEmpty) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            _DriverRecipientsStack(drivers: recipients),
          ],
          TextButton(
            onPressed: onCancel,
            child: const Text('إلغاء البحث'),
          ),
        ],
      ),
    );
  }
}

class _DriverRecipientsStack extends StatelessWidget {
  const _DriverRecipientsStack({required this.drivers});

  final List<NearbyDriver> drivers;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 30.0;
    const visibleCount = 5;
    const step = 16.0;
    final start = math.max(0, drivers.length - visibleCount);
    final visible =
        drivers.skip(start).take(visibleCount).toList(growable: false);
    final width = avatarSize + math.max(0, visible.length - 1) * step;
    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        children: <Widget>[
          for (var index = 0; index < visible.length; index++)
            Positioned(
              left: index * step,
              child: _DriverRecipientAvatar(driver: visible[index]),
            ),
        ],
      ),
    );
  }
}

class _DriverRecipientAvatar extends StatelessWidget {
  const _DriverRecipientAvatar({required this.driver});

  final NearbyDriver driver;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = driver.name.trim().isEmpty ? '؟' : driver.name.trim()[0];
    return Tooltip(
      message: driver.name,
      child: Container(
        width: 30,
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          border: Border.all(color: colors.surface, width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 4,
            ),
          ],
        ),
        child: ClipOval(
          child: driver.photoUrl.isNotEmpty
              ? Image.network(
                  driver.photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _DriverInitial(
                    initial: initial,
                    color: colors.primaryContainer,
                  ),
                )
              : _DriverInitial(
                  initial: initial,
                  color: colors.primaryContainer,
                ),
        ),
      ),
    );
  }
}

class _DriverInitial extends StatelessWidget {
  const _DriverInitial({required this.initial, required this.color});

  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: color,
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
      );
}

class _FloatingDriverOffers extends GetView<RideController> {
  const _FloatingDriverOffers();

  @override
  Widget build(BuildContext context) => Obx(() {
        if (controller.driverOffers.isEmpty) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 62, 12, 92),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: MediaQuery.sizeOf(context).height * .62,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: controller.driverOffers.length,
                  itemBuilder: (context, index) {
                    final offer = controller.driverOffers[index];
                    return _AnimatedOfferEntry(
                      key: ValueKey(offer.id),
                      removing: controller.removingOfferIds.contains(offer.id),
                      child: _DriverOfferCard(offer: offer),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      });
}

class _AnimatedOfferEntry extends StatelessWidget {
  const _AnimatedOfferEntry({
    required this.removing,
    required this.child,
    super.key,
  });

  final bool removing;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 320),
        tween: Tween<double>(end: removing ? 1 : 0),
        builder: (context, value, animatedChild) {
          final slide = Curves.easeIn.transform(value);
          final collapse = Curves.easeInOut.transform(
            ((value - .35) / .65).clamp(0.0, 1.0),
          );
          return ClipRect(
            child: Align(
              heightFactor: 1 - collapse,
              child: FractionalTranslation(
                translation: Offset(-1.15 * slide, 0),
                child: Opacity(
                  opacity: 1 - value,
                  child: animatedChild,
                ),
              ),
            ),
          );
        },
        child: child,
      );
}

class _DriverOfferCard extends StatefulWidget {
  const _DriverOfferCard({required this.offer});

  final DriverOffer offer;

  @override
  State<_DriverOfferCard> createState() => _DriverOfferCardState();
}

class _DriverOfferCardState extends State<_DriverOfferCard> {
  Timer? _timer;
  double _progress = 1;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _updateTimer();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      _updateTimer();
    });
  }

  void _updateTimer() {
    final expiresAt = widget.offer.expiresAt;
    if (expiresAt == null || widget.offer.status != DriverOfferStatus.pending) {
      if (_progress != 1 && mounted) setState(() => _progress = 1);
      return;
    }
    final remaining = expiresAt.difference(DateTime.now()).inMilliseconds;
    final createdAt = widget.offer.createdAt;
    final total = createdAt == null
        ? const Duration(minutes: 5).inMilliseconds
        : expiresAt.difference(createdAt).inMilliseconds;
    final progress = (remaining / total.clamp(1, 300000)).clamp(0.0, 1.0);
    final remainingSeconds = (remaining / 1000).ceil().clamp(0, 300);
    if (mounted) {
      setState(() {
        _progress = progress;
        _remainingSeconds = remainingSeconds;
      });
    }
    if (remaining <= 0) {
      _timer?.cancel();
      if (Get.isRegistered<RideController>()) {
        Get.find<RideController>().expireOffer(widget.offer);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 260),
        tween: Tween<double>(begin: 0, end: 1),
        builder: (context, value, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: widget.offer.status == DriverOfferStatus.rejected ||
                  widget.offer.status == DriverOfferStatus.expired
              ? .45
              : 1,
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 8,
            shadowColor: Colors.black38,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: const Icon(Icons.person_rounded),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.offer.driverName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(widget.offer.vehicleSummary),
                            Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 17,
                                ),
                                Text(
                                  ' ${widget.offer.rating}  •  ${widget.offer.etaMinutes} دقائق',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            '${widget.offer.price.toStringAsFixed(0)} ${Get.find<RideController>().quote.value?.currency ?? ''}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text('${widget.offer.etaMinutes} دقائق'),
                        ],
                      ),
                    ],
                  ),
                  if (widget.offer.status ==
                      DriverOfferStatus.pending) ...<Widget>[
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'offer_expires_in'.trParams(<String, String>{
                          'seconds': '$_remainingSeconds',
                        }),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 4,
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: .16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _TimedAcceptButton(
                            progress: _progress,
                            onPressed: () => Get.find<RideController>()
                                .acceptOffer(widget.offer),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: AppButton(
                            label: 'reject'.tr,
                            size: AppButtonSize.small,
                            variant: AppButtonVariant.outline,
                            onPressed: () => Get.find<RideController>()
                                .rejectOffer(widget.offer),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.offer.status == DriverOfferStatus.expired)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('offer_expired'.tr),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _TimedAcceptButton extends StatelessWidget {
  const _TimedAcceptButton({
    required this.progress,
    required this.onPressed,
  });

  final double progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 48,
      child: Material(
        color: primary,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimary
                        .withValues(alpha: .12),
                  ),
                ),
              ),
              Center(
                child: Text(
                  'accept_offer'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
