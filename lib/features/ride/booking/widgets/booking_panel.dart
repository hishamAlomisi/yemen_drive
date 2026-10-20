import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/cache/persistent_network_image.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../models/ride_models.dart';
import '../../models/service_kind_models.dart';
import '../../widgets/ride_booking_widgets.dart';
import '../../widgets/ride_vehicle_widgets.dart';
import '../controllers/booking_controller.dart';
import 'booking_service_widgets.dart';

class BookingPanel extends GetView<BookingController> {
  const BookingPanel({this.previewRoute, super.key});

  final Future<void> Function()? previewRoute;

  Future<void> _continue({
    int? field,
    RideHomeService? service,
    RideVehicle? vehicle,
  }) =>
      controller.continueFromHome(
        editField: field,
        service: service,
        vehicle: vehicle,
        previewRoute: previewRoute,
      );

  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = controller.ride;
        final location = controller.location;
        final colors = Theme.of(context).colorScheme;
        final selectedKind = ride.homeServices
            .where((item) => item.id == ride.selectedServiceKindId.value)
            .firstOrNull;
        final enabled =
            !ride.bookingLocked && !controller.isOpeningHomeBooking.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const ValueKey('home-route-search'),
                      onTap: enabled
                          ? () => _continue(
                                field: location.pickup.value == null ? 0 : 1,
                              )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 17,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded, size: 27),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'home_where_and_fare'.tr,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (location.hasCompleteRoute) ...[
                    const SizedBox(height: 10),
                    BookingAddressRow(
                      key: const ValueKey('home-pickup'),
                      textController: location.fromController,
                      hint: 'booking_pickup'.tr,
                      icon: Icons.radio_button_checked_rounded,
                      iconColor: colors.primary,
                      onTap: enabled ? () => _continue(field: 0) : null,
                    ),
                    const SizedBox(height: 4),
                    BookingAddressRow(
                      key: const ValueKey('home-destination'),
                      textController: location.toController,
                      hint: 'booking_destination'.tr,
                      icon: Icons.location_on_outlined,
                      onTap: enabled ? () => _continue(field: 1) : null,
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: location.detailsController,
                      builder: (_, value, __) => TextButton.icon(
                        key: const ValueKey('home-address-details'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.onPrimaryContainer,
                          backgroundColor: colors.primaryContainer,
                          alignment: AlignmentDirectional.centerStart,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed: enabled ? () => _showDetails(context) : null,
                        icon: const Icon(Icons.edit_note_outlined, size: 22),
                        label: Text(
                          value.text.isEmpty
                              ? 'home_address_details'.tr
                              : value.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            _HomeSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'booking_services'.tr,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  if (ride.isHomeServicesLoading.value)
                    const LinearProgressIndicator()
                  else if (ride.homeServicesError.value.isNotEmpty ||
                      ride.homeServices.isEmpty)
                    _BookingNotice(
                      message: ride.homeServicesError.value.isNotEmpty
                          ? ride.homeServicesError.value
                          : 'home_no_services'.tr,
                      onRetry: ride.loadHomeServices,
                    )
                  else
                    BookingServiceKindsStrip(
                      services: ride.homeServices.toList(growable: false),
                      selectedId: ride.selectedServiceKindId.value,
                      onSelected: enabled
                          ? (service) => _continue(service: service)
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _HomeSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      BookingServiceImage(service: selectedKind, size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          selectedKind == null
                              ? 'home_choose_service'.tr
                              : 'home_service_items'
                                  .trParams({'service': selectedKind.name}),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const Icon(Icons.swipe_rounded, size: 18),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (ride.isCatalogLoading.value)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: LinearProgressIndicator(),
                    )
                  else if (ride.catalogError.value.isNotEmpty)
                    _BookingNotice(
                      message: ride.catalogError.value,
                      onRetry: ride.selectedServiceKindId.value == null
                          ? null
                          : () => ride.loadServiceCatalog(),
                    )
                  else if (ride.vehicles.isNotEmpty)
                    SizedBox(
                      height: 106 *
                          MediaQuery.textScalerOf(context)
                              .scale(1)
                              .clamp(1.0, 1.5),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: ride.vehicles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final vehicle = ride.vehicles[index];
                          return BookingVehicleTile(
                            vehicle: vehicle,
                            selected:
                                ride.selectedVehicle.value?.id == vehicle.id,
                            onTap: enabled
                                ? () => _continue(vehicle: vehicle)
                                : null,
                          );
                        },
                      ),
                    )
                  else
                    Text(
                      'home_no_items'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (location.isRouteLoading.value ||
                controller.isOpeningHomeBooking.value)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (location.serviceAreaAvailable.value == false)
              const _BookingNotice(
                message: 'الخدمة غير متوفرة في هذه المنطقة حالياً',
              )
            else if (location.hasCompleteRoute &&
                !location.hasDrivingRoute &&
                !location.isRouteLoading.value)
              _BookingNotice(
                message: 'تعذر تحديد طريق الوصول',
                onRetry: location.retryDrivingRoute,
              ),
            if (ride.quoteError.value.isNotEmpty)
              _BookingNotice(
                message: ride.quoteError.value,
                onRetry: controller.refreshQuote,
              ),
          ],
        );
      });

  Future<void> _showDetails(BuildContext context) async {
    final location = controller.location;
    final selection = controller.selectionKey;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => BookingDetailsSheet(
        name: location.addressNameController.text,
        details: location.detailsController.text,
      ),
    );
    if (result == null ||
        controller.ride.bookingLocked ||
        selection != controller.selectionKey) {
      return;
    }
    location.addressNameController.text = result.$1;
    location.detailsController.text = result.$2;
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      );
}

class BookingContinueBar extends GetView<BookingController> {
  const BookingContinueBar({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AppButton(
          label: 'متابعة الطلب',
          onPressed: controller.canSubmit ? controller.openReview : null,
          leading: const Icon(Icons.arrow_back_rounded),
        ),
      );
}

class BookingSubmitBar extends GetView<BookingController> {
  const BookingSubmitBar({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => BookingActionBar(
          label: 'booking_search'.tr,
          onPressed: controller.canSubmit ? controller.submit : null,
          isLoading: controller.ride.isSubmittingRequest.value,
          paymentButton: const RidePaymentPreferenceButton(),
        ),
      );
}

class BookingVehicleTile extends StatelessWidget {
  const BookingVehicleTile({
    required this.vehicle,
    required this.selected,
    this.onTap,
    super.key,
  });
  final RideVehicle vehicle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = vehicle.imageAsset;
    final fallback = Icon(vehicle.type.icon, size: 40, color: colors.onSurface);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 106,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Expanded(
                    child: source != null && source.startsWith('http')
                        ? PersistentNetworkImage(
                            source,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => fallback,
                          )
                        : fallback,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    vehicle.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_outline, size: 14),
                      Text(
                        ' ${vehicle.seats}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check, size: 16),
                      ],
                    ],
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

class BookingAddressRow extends StatelessWidget {
  const BookingAddressRow({
    required this.textController,
    required this.hint,
    required this.icon,
    this.iconColor,
    this.onTap,
    this.filled = false,
    super.key,
  });
  final TextEditingController textController;
  final String hint;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Material(
        color: filled
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: textController,
                    builder: (_, value, __) => Text(
                      value.text.trim().isEmpty ? hint : value.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_left, size: 18),
              ],
            ),
          ),
        ),
      );
}

class BookingFareRow extends GetView<BookingController> {
  const BookingFareRow({this.showAmount = true, super.key});

  final bool showAmount;

  @override
  Widget build(BuildContext context) => Obx(() {
        final ride = controller.ride;
        final quote = ride.quote.value;
        final loading =
            ride.negotiationStatus.value == NegotiationStatus.quoting;
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: quote == null || ride.bookingLocked
                ? null
                : () async {
                    final selection = controller.selectionKey;
                    final price = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      useSafeArea: true,
                      isScrollControlled: true,
                      builder: (_) => BookingFareSheet(
                        currentPrice: ride.offeredPrice.value,
                        suggestedPrice: quote.suggestedPrice,
                        minPrice: quote.minPrice,
                        maxPrice: quote.maxPrice,
                        currency: quote.currency,
                      ),
                    );
                    if (price != null &&
                        selection == controller.selectionKey &&
                        identical(quote, ride.quote.value)) {
                      ride.setBookingPrice(price);
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Text(
                    quote?.currency ?? 'ر.ي',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loading
                              ? 'جاري حساب الأجرة…'
                              : quote == null
                                  ? 'حدد المسار لاقتراح الأجرة'
                                  : showAmount
                                      ? '${ride.offeredPrice.value.toStringAsFixed(0)} · أجرتك المقترحة'
                                      : 'تعديل أجرة الرحلة',
                        ),
                        if (showAmount && quote != null && quote.serviceFee > 0)
                          Text(
                            'رسوم الخدمة ${quote.serviceFee.toStringAsFixed(0)} ${quote.currency}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.edit_outlined, size: 20),
                ],
              ),
            ),
          ),
        );
      });
}

class BookingFareSheet extends StatefulWidget {
  const BookingFareSheet({
    required this.currentPrice,
    required this.suggestedPrice,
    this.minPrice = 1,
    this.maxPrice = 999999999,
    required this.currency,
    super.key,
  });
  final double currentPrice;
  final double suggestedPrice;
  final double minPrice;
  final double maxPrice;
  final String currency;
  @override
  State<BookingFareSheet> createState() => _BookingFareSheetState();
}

class _BookingFareSheetState extends State<BookingFareSheet> {
  late final _price =
      TextEditingController(text: widget.currentPrice.toStringAsFixed(0));
  String? _error;

  void _save() {
    var text = _price.text.trim();
    for (var i = 0; i < 10; i++) {
      text = text
          .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
          .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
    }
    final value = int.tryParse(text);
    if (value == null || value <= 0 || value > 999999999) {
      setState(() => _error = 'أدخل أجرة صحيحة أكبر من صفر');
      return;
    }
    if (value < widget.minPrice || value > widget.maxPrice) {
      setState(() => _error =
          'الأجرة المسموحة من ${widget.minPrice.toStringAsFixed(0)} إلى ${widget.maxPrice.toStringAsFixed(0)} ${widget.currency}');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => _BookingSheet(
        title: 'اقترح أجرتك',
        children: [
          Text(
            'الأجرة المقترحة ${widget.suggestedPrice.toStringAsFixed(0)} ${widget.currency}',
          ),
          Text(
              'المسموح: ${widget.minPrice.toStringAsFixed(0)} – ${widget.maxPrice.toStringAsFixed(0)} ${widget.currency}'),
          const SizedBox(height: 16),
          TextField(
            controller: _price,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
              LengthLimitingTextInputFormatter(9),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'أجرتك',
              suffixText: widget.currency,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          const Text('سيصلك عرض السائق لتراجعه قبل القبول.'),
          const SizedBox(height: 20),
          AppButton(label: 'تم', onPressed: _save),
        ],
      );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }
}

class BookingDetailsSheet extends StatefulWidget {
  const BookingDetailsSheet({
    required this.name,
    required this.details,
    super.key,
  });
  final String name;
  final String details;
  @override
  State<BookingDetailsSheet> createState() => _BookingDetailsSheetState();
}

class _BookingDetailsSheetState extends State<BookingDetailsSheet> {
  late final _name = TextEditingController(text: widget.name);
  late final _details = TextEditingController(text: widget.details);
  @override
  Widget build(BuildContext context) => _BookingSheet(
        title: 'تفاصيل الوصول',
        children: [
          TextField(
            controller: _name,
            maxLength: 100,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'اسم المكان (اختياري)',
              hintText: 'المنزل، العمل…',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'علامة مميزة أو مدخل المبنى',
              hintText: 'تفاصيل تساعد السائق في الوصول',
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'تم',
            onPressed: () => Navigator.pop(
              context,
              (_name.text.trim(), _details.text.trim()),
            ),
          ),
        ],
      );
  @override
  void dispose() {
    _name.dispose();
    _details.dispose();
    super.dispose();
  }
}

class _BookingSheet extends StatelessWidget {
  const _BookingSheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      );
}

class _BookingNotice extends StatelessWidget {
  const _BookingNotice({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('إعادة المحاولة'),
              ),
          ],
        ),
      );
}
