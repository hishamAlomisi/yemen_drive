import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/cache/persistent_network_image.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../models/ride_models.dart';
import '../../widgets/ride_booking_widgets.dart';
import '../../widgets/ride_vehicle_widgets.dart';
import '../controllers/booking_controller.dart';
import 'booking_panel.dart';
import 'ride_options_sheet.dart';

class BookingReviewPanel extends GetView<BookingController> {
  const BookingReviewPanel({super.key});
  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = controller.ride;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ride.selectedVehicle.value == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  'review_choose_service'.tr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            for (final vehicle in ride.vehicles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReviewService(vehicle: vehicle),
              ),
            if (ride.quoteError.value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      ride.quoteError.value,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          controller.canQuote ? controller.refreshQuote : null,
                      icon: const Icon(Icons.refresh),
                      label: Text('review_retry'.tr),
                    ),
                  ],
                ),
              ),
            if (controller.failedReviewQuotes.isNotEmpty)
              TextButton.icon(
                onPressed: () => controller.loadReviewQuotes(retry: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text('review_retry_prices'.tr),
              ),
          ],
        );
      });
}

class _ReviewService extends GetView<BookingController> {
  const _ReviewService({required this.vehicle});
  final RideVehicle vehicle;

  Future<void> _editPrice(BuildContext context) async {
    final quote = controller.ride.quote.value;
    if (quote == null || controller.ride.bookingLocked) return;
    final selection = controller.selectionKey;
    final price = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => BookingFareSheet(
        currentPrice: controller.ride.offeredPrice.value,
        suggestedPrice: quote.suggestedPrice,
        minPrice: quote.minPrice,
        maxPrice: quote.maxPrice,
        currency: quote.currency,
      ),
    );
    if (price != null &&
        selection == controller.selectionKey &&
        identical(quote, controller.ride.quote.value)) {
      controller.ride.setBookingPrice(price);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = controller.ride;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final selected = ride.selectedVehicle.value?.id == vehicle.id;
        final quote =
            selected ? ride.quote.value : controller.reviewQuotes[vehicle.id];
        final loading = selected
            ? ride.negotiationStatus.value == NegotiationStatus.quoting
            : controller.loadingReviewQuotes.contains(vehicle.id);
        final canEdit = selected && controller.canSubmit;
        return Semantics(
          selected: selected,
          button: true,
          child: AnimatedContainer(
            key: ValueKey('review-service-${vehicle.id}'),
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              color: selected ? colors.surfaceContainerLow : colors.surface,
              borderRadius: BorderRadius.circular(24),
              border: selected
                  ? Border.all(color: colors.outlineVariant, width: 1.5)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: selected && colors.brightness == Brightness.dark
                      ? colors.surfaceContainer
                      : colors.surface,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: ride.bookingLocked
                        ? null
                        : () => controller.chooseReviewVehicle(vehicle),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 62,
                            height: 52,
                            child: BookingVehicleImage(vehicle: vehicle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicle.name,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 5,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (vehicle.seats > 0) ...[
                                      const Icon(
                                        Icons.person_rounded,
                                        size: 16,
                                      ),
                                      Text(
                                        '${vehicle.seats}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                    if (vehicle.arrivalMinutes > 0)
                                      Text(
                                        '· ${'review_eta'.trParams({
                                              'minutes':
                                                  '${vehicle.arrivalMinutes}',
                                            })}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                                if (vehicle.description.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    vehicle.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (selected)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'review_edit_fare'.tr,
                                  onPressed: canEdit
                                      ? () => _editPrice(context)
                                      : null,
                                  icon: const Icon(
                                    Icons.edit_rounded,
                                    size: 19,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'review_invoice'.tr,
                                  onPressed: quote == null
                                      ? null
                                      : () => showBookingPriceDetails(context),
                                  icon: const Icon(
                                    Icons.info_outline_rounded,
                                    size: 19,
                                  ),
                                ),
                              ],
                            )
                          else
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      quote == null
                                          ? 'review_price_unavailable'.tr
                                          : '~ ${quote.suggestedPrice.toStringAsFixed(0)} ${quote.currency}',
                                      textDirection: TextDirection.ltr,
                                      textAlign: TextAlign.end,
                                      style: theme.textTheme.titleSmall,
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 13,
                    ),
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'زيادة السعر',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(46, 46),
                            backgroundColor: colors.surface,
                            foregroundColor: colors.onSurface,
                          ),
                          onPressed: canEdit &&
                                  ride.offeredPrice.value <
                                      ride.maximumBookingPrice
                              ? ride.increasePrice
                              : null,
                          icon: const Icon(Icons.add, size: 27),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: InkWell(
                            onTap: canEdit ? () => _editPrice(context) : null,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (loading)
                                  const LinearProgressIndicator()
                                else
                                  Text(
                                    quote == null
                                        ? 'review_calculating'.tr
                                        : '${ride.offeredPrice.value.toStringAsFixed(0)} ${quote.currency}',
                                    key: const ValueKey(
                                      'review-fare',
                                    ),
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'review_suggested_fare'.tr,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        IconButton.filledTonal(
                          tooltip: 'إنقاص السعر',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(46, 46),
                            backgroundColor: colors.surface,
                            foregroundColor: colors.onSurface,
                          ),
                          onPressed: canEdit &&
                                  ride.offeredPrice.value >
                                      ride.minimumBookingPrice
                              ? ride.decreasePrice
                              : null,
                          icon: const Icon(Icons.remove, size: 27),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      });
}

class BookingVehicleImage extends StatelessWidget {
  const BookingVehicleImage({required this.vehicle, super.key});
  final RideVehicle vehicle;
  @override
  Widget build(BuildContext context) {
    final source = vehicle.imageAsset?.trim() ?? '';
    final fallback = Icon(
      vehicle.type.icon,
      size: 42,
      color: Theme.of(context).colorScheme.onSurface,
    );
    if (source.isEmpty) return fallback;
    return source.startsWith('http')
        ? PersistentNetworkImage(
            source,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback,
          )
        : Image.asset(
            source,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback,
          );
  }
}

class BookingReviewFooter extends GetView<BookingController> {
  const BookingReviewFooter({super.key});
  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = controller.ride;
        final theme = Theme.of(context);
        final quote = ride.quote.value;
        return Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.near_me_rounded, size: 23),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          quote == null
                              ? 'review_auto_accept'.tr
                              : 'review_auto_accept_price'.trParams({
                                  'price':
                                      '${ride.offeredPrice.value.toStringAsFixed(0)} ${quote.currency}',
                                }),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Switch(
                        value: ride.autoAcceptMatchingPrice.value,
                        onChanged: controller.canSubmit
                            ? (value) =>
                                ride.autoAcceptMatchingPrice.value = value
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      IconButton(
                        tooltip: 'review_options'.tr,
                        onPressed: ride.bookingLocked
                            ? null
                            : () => showBookingOptions(context),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: AppButton(
                          label: 'booking_search'.tr,
                          onPressed:
                              controller.canSubmit ? controller.submit : null,
                          isLoading: ride.isSubmittingRequest.value,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const RidePaymentPreferenceButton(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      });
}

Future<void> showBookingArrivalDetails(BuildContext context) async {
  final booking = Get.find<BookingController>();
  final selection = booking.selectionKey;
  final result = await showModalBottomSheet<(String, String)>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => BookingDetailsSheet(
      name: booking.location.addressNameController.text,
      details: booking.location.detailsController.text,
    ),
  );
  if (result != null &&
      !booking.ride.bookingLocked &&
      selection == booking.selectionKey) {
    booking.location.addressNameController.text = result.$1;
    booking.location.detailsController.text = result.$2;
  }
}

Future<void> showBookingOptions(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.airline_seat_recline_normal),
              title: const Text('أضف خيارات الركوب'),
              onTap: () {
                Navigator.pop(sheetContext);
                showRideOptions(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: Text('home_address_details'.tr),
              onTap: () {
                Navigator.pop(sheetContext);
                showBookingArrivalDetails(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text('review_invoice'.tr),
              onTap: () {
                Navigator.pop(sheetContext);
                showBookingPriceDetails(context);
              },
            ),
          ],
        ),
      ),
    );

Future<void> showBookingPriceDetails(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const BookingPriceDetails(),
    );

class BookingPriceDetails extends GetView<BookingController> {
  const BookingPriceDetails({super.key});
  @override
  Widget build(BuildContext context) => Obx(() {
        final quote = controller.ride.quote.value;
        final location = controller.location;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'review_invoice'.tr,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final field in [
                  (location.addressNameController, 'review_place_name'),
                  (location.streetController, 'review_street'),
                  (location.detailsController, 'review_arrival_details'),
                ])
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: field.$1,
                    builder: (_, value, __) => value.text.trim().isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${field.$2.tr}: ${value.text.trim()}',
                            ),
                          ),
                  ),
                if (quote != null) ...[
                  const SizedBox(height: 20),
                  _InvoiceLine(
                    label: 'review_fare'.tr,
                    amount: controller.ride.offeredPrice.value,
                    currency: quote.currency,
                  ),
                  const SizedBox(height: 8),
                  _InvoiceLine(
                    label: 'review_fee'.tr,
                    amount: quote.serviceFee,
                    currency: quote.currency,
                  ),
                  const Divider(height: 24),
                  _InvoiceLine(
                    key: const ValueKey('review-total'),
                    label: 'review_total'.tr,
                    amount:
                        quote.totalForFare(controller.ride.offeredPrice.value),
                    currency: quote.currency,
                    emphasized: true,
                  ),
                ],
              ],
            ),
          ),
        );
      });
}

class _InvoiceLine extends StatelessWidget {
  const _InvoiceLine({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasized = false,
    super.key,
  });
  final String label;
  final double amount;
  final String currency;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              '${amount.toStringAsFixed(0)} $currency',
              style:
                  emphasized ? Theme.of(context).textTheme.titleMedium : null,
            ),
          ),
        ],
      );
}
