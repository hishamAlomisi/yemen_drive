import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/cache/persistent_network_image.dart';
import '../../../../core/config/app_environment.dart';
import '../../controllers/ride_controller.dart';
import '../../models/ride_models.dart';
import '../../ride_routes.dart';
import '../../widgets/ride_map_shell.dart';

class RideSearchView extends StatefulWidget {
  const RideSearchView(
      {required this.onCancel, this.offerCards = const [], super.key});
  final VoidCallback onCancel;
  final List<Widget> offerCards;

  @override
  State<RideSearchView> createState() => _RideSearchViewState();
}

class _RideSearchViewState extends State<RideSearchView> {
  final RideController _ride = Get.find<RideController>();
  Worker? _exhaustedWorker;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _exhaustedWorker = ever(_ride.offersExhausted, (_) => _showExhausted());
    WidgetsBinding.instance.addPostFrameCallback((_) => _showExhausted());
  }

  Future<void> _showExhausted() async {
    if (!mounted ||
        _dialogOpen ||
        !_ride.offersExhausted.value ||
        Get.currentRoute != RideRoutes.negotiationQuote) return;
    _dialogOpen = true;
    final retry = await Get.dialog<bool>(
        AlertDialog(
          title: Text('search_timeout_title'.tr),
          content: Text('search_timeout_body'.tr),
          actions: [
            TextButton(
                onPressed: () => Get.back<bool>(result: false),
                child: Text('search_cancel'.tr)),
            FilledButton(
                onPressed: () => Get.back<bool>(result: true),
                child: Text('search_retry'.tr)),
          ],
        ),
        barrierDismissible: false);
    _dialogOpen = false;
    if (!mounted || retry == null) return;
    _ride.acknowledgeOffersExhausted();
    if (retry) {
      await _ride.retryDriverSearch();
    } else {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        if (_ride.driverOffers.isNotEmpty && widget.offerCards.isNotEmpty) {
          return RideMapShell(
            panel: const SizedBox.shrink(),
            showPanel: false,
            showRoute: true,
            showRouteGuide: false,
            showMarker: false,
            foregroundOverlay: ColoredBox(
              color: Colors.black.withValues(alpha: .48),
              child: SafeArea(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FilledButton.tonalIcon(
                              onPressed: widget.onCancel,
                              icon: const Icon(Icons.close),
                              label: const Text('إلغاء الطلب'))),
                      const SizedBox(height: 18),
                      Text('اختيار سائق',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: Colors.white)),
                      const SizedBox(height: 16),
                      Expanded(child: ListView(children: widget.offerCards)),
                    ]),
              )),
            ),
          );
        }
        return RideMapShell(
          panel: const SizedBox.shrink(),
          showPanel: false,
          showRoute: true,
          showRouteGuide: false,
          showMarker: false,
          showPassengerSearchRadar: _ride.isSearchingForDriver.value,
          foregroundOverlay: DraggableScrollableSheet(
            key: const ValueKey('search-sheet'),
            minChildSize: .16,
            initialChildSize: .79,
            maxChildSize: .97,
            snap: true,
            snapSizes: const [.16, .79, .97],
            builder: (context, scroll) => Obx(() => Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(26)),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                      top: false,
                      child: Column(children: [
                        Expanded(
                            child: ListView(
                          controller: scroll,
                          padding: EdgeInsets.zero,
                          children: [
                            const SearchRequestViewers(),
                            _section(
                                context,
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Center(
                                          child: Container(
                                              width: 42,
                                              height: 5,
                                              margin: const EdgeInsets.only(
                                                  bottom: 20),
                                              decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          5)))),
                                      Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(
                                                      widget.offerCards
                                                              .isNotEmpty
                                                          ? 'search_choose_driver'
                                                              .tr
                                                          : 'search_waiting'.tr,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleLarge
                                                          ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800)),
                                                  Text('search_you_choose'.tr,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyLarge),
                                                ])),
                                            const SizedBox(width: 8),
                                            Text(
                                                _time(_ride
                                                    .searchRemainingSeconds
                                                    .value),
                                                key: const ValueKey(
                                                    'search-countdown'),
                                                textDirection:
                                                    TextDirection.ltr,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineSmall
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                          ]),
                                      const SizedBox(height: 16),
                                      LinearProgressIndicator(
                                          key:
                                              const ValueKey('search-progress'),
                                          value: _ride.searchRemainingSeconds
                                                  .value /
                                              60,
                                          minHeight: 4,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerLow),
                                      ...widget.offerCards,
                                      const SizedBox(height: 18),
                                      const SearchRequestFare(),
                                      const SizedBox(height: 10),
                                      FilledButton(
                                        key: const ValueKey(
                                            'search-confirm-price'),
                                        onPressed: _ride.canConfirmSearchPrice
                                            ? _ride.confirmSearchPrice
                                            : null,
                                        style: FilledButton.styleFrom(
                                            disabledBackgroundColor:
                                                Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerLow,
                                            disabledForegroundColor:
                                                Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: .30),
                                            minimumSize:
                                                const Size.fromHeight(50),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18))),
                                        child: _ride.isUpdatingSearchPrice.value
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : Text('search_confirm'.tr),
                                      ),
                                    ])),
                            const SizedBox(height: 6),
                            _section(
                                context,
                                Row(children: [
                                  const Icon(Icons.near_me_rounded, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(
                                          'search_auto_accept'.trParams(
                                              {'price': _fare(_ride)}),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge)),
                                  Switch.adaptive(
                                      value:
                                          _ride.autoAcceptMatchingPrice.value,
                                      onChanged:
                                          _ride.isSearchingForDriver.value
                                              ? (value) => _ride
                                                  .autoAcceptMatchingPrice
                                                  .value = value
                                              : null),
                                ])),
                            const SizedBox(height: 6),
                            _section(
                                context,
                                Row(children: [
                                  Icon(
                                      _ride.preferredPaymentMethod.value ==
                                              'cash'
                                          ? Icons.payments_rounded
                                          : Icons
                                              .account_balance_wallet_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 12),
                                  Flexible(
                                      child: Text(_fare(_ride),
                                          textDirection: TextDirection.ltr,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge)),
                                  const SizedBox(width: 10),
                                  Flexible(
                                      child: Text(
                                          _paymentLabel(_ride
                                              .preferredPaymentMethod.value),
                                          key: const ValueKey(
                                              'search-payment-method'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge)),
                                ])),
                            const SizedBox(height: 6),
                            _section(
                                context,
                                Column(children: [
                                  _address(
                                      context,
                                      Icons.hail_rounded,
                                      _ride.currentDraft.value?.pickupAddress ??
                                          ''),
                                  const Padding(
                                      padding:
                                          EdgeInsetsDirectional.only(start: 13),
                                      child: Align(
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: SizedBox(
                                              height: 14,
                                              child: VerticalDivider(
                                                  width: 1, thickness: 1)))),
                                  _address(
                                      context,
                                      Icons.flag_rounded,
                                      _ride.currentDraft.value
                                              ?.destinationAddress ??
                                          ''),
                                ])),
                            const SizedBox(height: 6),
                          ],
                        )),
                        _section(
                            context,
                            SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  key: const ValueKey('search-cancel'),
                                  onPressed: widget.onCancel,
                                  style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18))),
                                  child: Text('search_cancel'.tr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                ))),
                      ])),
                )),
          ),
        );
      });

  Widget _section(BuildContext context, Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(26)),
      child: child);

  Widget _address(BuildContext context, IconData icon, String text) =>
      Row(children: [
        Icon(icon, size: 27),
        const SizedBox(width: 12),
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge))
      ]);

  String _time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  String _paymentLabel(String value) => value == 'cash'
      ? 'booking_cash'.tr
      : value == 'wallet'
          ? 'booking_wallet'.tr
          : AppEnvironment.paymentMethodById(value)?.label ??
              'booking_external_wallets'.tr;

  @override
  void dispose() {
    _exhaustedWorker?.dispose();
    super.dispose();
  }
}

String _fare(RideController ride) =>
    '${(ride.currentDraft.value?.offeredPrice ?? ride.offeredPrice.value).toStringAsFixed(0)} ${ride.quote.value?.currency ?? AppEnvironment.defaultCurrency}';

class SearchRequestFare extends GetView<RideController> {
  const SearchRequestFare({super.key});
  @override
  Widget build(BuildContext context) => Obx(() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22)),
        child: Row(textDirection: TextDirection.ltr, children: [
          IconButton.filledTonal(
              key: const ValueKey('search-price-plus'),
              tooltip: 'search_price_increase'.tr,
              onPressed: controller.canChangeSearchPrice &&
                      controller.pendingSearchPrice.value <
                          controller.maximumBookingPrice
                  ? () => controller.changeSearchPrice(1)
                  : null,
              style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  minimumSize: const Size(52, 52)),
              icon: const Icon(Icons.add, size: 28)),
          const SizedBox(width: 6),
          Expanded(
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      '${controller.pendingSearchPrice.value.toStringAsFixed(0)} ${controller.quote.value?.currency ?? AppEnvironment.defaultCurrency}',
                      key: const ValueKey('search-price'),
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)))),
          const SizedBox(width: 6),
          IconButton.filledTonal(
              key: const ValueKey('search-price-minus'),
              tooltip: 'search_price_decrease'.tr,
              onPressed: controller.canChangeSearchPrice &&
                      controller.pendingSearchPrice.value >
                          controller.minimumBookingPrice
                  ? () => controller.changeSearchPrice(-1)
                  : null,
              style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  minimumSize: const Size(52, 52)),
              icon: const Icon(Icons.remove, size: 28)),
        ]),
      ));
}

class SearchRequestViewers extends GetView<RideController> {
  const SearchRequestViewers({super.key});
  @override
  Widget build(BuildContext context) => Obx(() {
        final viewers = controller.requestViewers.toList(growable: false);
        final visible = viewers.take(5).toList(growable: false);
        final extra = viewers.length - visible.length;
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(
                  child: Text(
                      viewers.isEmpty
                          ? 'search_no_viewers'.tr
                          : 'search_viewers'
                              .trParams({'count': '${viewers.length}'}),
                      key: const ValueKey('search-viewers-count'),
                      style: Theme.of(context).textTheme.bodyLarge)),
              if (viewers.isNotEmpty) ...[
                const SizedBox(width: 10),
                SizedBox(
                    width: 34 + (visible.length - 1 + (extra > 0 ? 1 : 0)) * 23,
                    height: 36,
                    child: Stack(children: [
                      for (var i = 0; i < visible.length; i++)
                        PositionedDirectional(
                            end: i * 23,
                            child: _ViewerAvatar(viewer: visible[i])),
                      if (extra > 0)
                        PositionedDirectional(
                            end: visible.length * 23,
                            child: CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    Theme.of(context).colorScheme.surface,
                                child: Text('+$extra',
                                    textDirection: TextDirection.ltr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall))),
                    ])),
              ],
            ]));
      });
}

class _ViewerAvatar extends StatelessWidget {
  const _ViewerAvatar({required this.viewer});
  final RideRequestViewer viewer;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: viewer.name,
      child: Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface),
          child: ClipOval(
              child: viewer.photoUrl?.isNotEmpty == true
                  ? PersistentNetworkImage(viewer.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.person))
                  : ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.person, size: 24)))));
}
