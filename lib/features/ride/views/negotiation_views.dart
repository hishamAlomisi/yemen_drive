import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/cache/persistent_network_image.dart';
import '../booking/views/booking_review_view.dart';
import '../booking/views/ride_search_view.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../ride_routes.dart';

class NegotiationQuotePage extends StatefulWidget {
  const NegotiationQuotePage({super.key});
  @override
  State<NegotiationQuotePage> createState() => _NegotiationQuotePageState();
}

class _NegotiationQuotePageState extends State<NegotiationQuotePage> {
  final RideController controller = Get.find<RideController>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.resumePendingRequestIfNeeded();
    });
  }

  void _back() {
    if (controller.currentRideId != null) {
      Get.toNamed<void>(RideRoutes.rideCancel);
    } else {
      controller.cancelPendingQuote();
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final hasRequest = controller.currentRideId != null;
        return PopScope(
          canPop: !hasRequest && !controller.isSubmittingRequest.value,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              controller.cancelPendingQuote();
            } else if (hasRequest) {
              _back();
            }
          },
          child: !hasRequest
              ? BookingReviewView(onClose: _back)
              : RideSearchView(onCancel: _back, offerCards: [
                  for (final offer in controller.driverOffers)
                    _AnimatedOfferEntry(
                        key: ValueKey(offer.id),
                        removing:
                            controller.removingOfferIds.contains(offer.id),
                        child: _DriverOfferCard(offer: offer)),
                ]),
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
        ? const Duration(minutes: 1).inMilliseconds
        : expiresAt.difference(createdAt).inMilliseconds;
    final progress = (remaining / total.clamp(1, 60000)).clamp(0.0, 1.0);
    final remainingSeconds = (remaining / 1000).ceil().clamp(0, 60);
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
  Widget build(BuildContext context) => Obx(() {
        final ride = Get.find<RideController>();
        final pending = widget.offer.status == DriverOfferStatus.pending &&
            (widget.offer.expiresAt == null || _remainingSeconds > 0);
        return DriverOfferTile(
          offer: widget.offer,
          currency: ride.quote.value?.currency ?? 'ر.ي',
          progress: widget.offer.expiresAt == null ? null : _progress,
          remainingSeconds: _remainingSeconds,
          busy: ride.isRespondingToOffer.value,
          onAccept: pending ? () => ride.acceptOffer(widget.offer) : null,
          onReject: pending ? () => ride.rejectOffer(widget.offer) : null,
        );
      });
}

class DriverOfferTile extends StatelessWidget {
  const DriverOfferTile(
      {required this.offer,
      required this.currency,
      this.progress,
      this.remainingSeconds = 0,
      this.busy = false,
      this.onAccept,
      this.onReject,
      super.key});
  final DriverOffer offer;
  final String currency;
  final double? progress;
  final int remainingSeconds;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
              radius: 25,
              backgroundColor: theme.colorScheme.surfaceContainer,
              child: offer.photoUrl?.isNotEmpty == true
                  ? ClipOval(
                      child: PersistentNetworkImage(offer.photoUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.person_outline)))
                  : Icon(Icons.person_outline,
                      color: theme.colorScheme.onSurface)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(offer.driverName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 3),
                Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFF7BD3B), size: 18),
                        Text(offer.rating > 0
                            ? offer.rating.toStringAsFixed(1)
                            : '—'),
                      ]),
                      if (offer.etaMinutes > 0)
                        Text(offer.etaMinutes.toString() + ' دقائق'),
                    ]),
              ])),
        ]),
        if (offer.vehicleSummary.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(offer.vehicleSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              flex: 2,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.price.toStringAsFixed(0),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall),
                    Text(currency, style: theme.textTheme.bodySmall),
                  ])),
          const SizedBox(width: 8),
          Expanded(
              flex: 3,
              child: Semantics(
                button: true,
                label: 'قبول العرض، متبقٍ $remainingSeconds ثانية',
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: InkWell(
                        onTap: busy ? null : onAccept,
                        child: SizedBox(
                            height: 52,
                            child: Stack(fit: StackFit.expand, children: [
                              if (onAccept != null)
                                FractionallySizedBox(
                                    alignment: AlignmentDirectional.centerStart,
                                    widthFactor: progress ?? 1,
                                    child: ColoredBox(
                                        color: theme
                                            .colorScheme.primaryContainer)),
                              Center(
                                  child: Text(
                                      progress == null
                                          ? 'قبول'
                                          : 'قبول · $remainingSeconds ث',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurface))),
                            ])),
                      ),
                    )),
              )),
          const SizedBox(width: 8),
          TextButton(
              onPressed: busy ? null : onReject, child: const Text('رفض')),
        ]),
        if (progress != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 4),
          Text(
              'offer_expires_in'
                  .trParams({'seconds': remainingSeconds.toString()}),
              style: theme.textTheme.labelSmall),
        ],
      ]),
    );
  }
}
