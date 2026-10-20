import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../shared/widgets/app_google_map.dart';
import '../../widgets/ride_common_widgets.dart';
import '../controllers/booking_controller.dart';
import '../widgets/booking_review_panel.dart';

class BookingReviewView extends StatefulWidget {
  const BookingReviewView({required this.onClose, super.key});
  final VoidCallback onClose;
  @override
  State<BookingReviewView> createState() => _BookingReviewViewState();
}

class _BookingReviewViewState extends State<BookingReviewView> {
  final BookingController booking = Get.find<BookingController>();
  final DraggableScrollableController _sheet = DraggableScrollableController();
  final ValueNotifier<double> _extent = ValueNotifier(.62);
  Timer? _focusTimer;
  int _focusRevision = 0;
  Worker? _mapSelectionWorker;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_sheetChanged);
    _mapSelectionWorker =
        ever(booking.location.isChoosingMapPoint, (bool choosing) {
      if (choosing && _sheet.isAttached) {
        unawaited(
          _sheet.animateTo(
            .18,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubic,
          ),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) booking.reviewOpened();
    });
  }

  void _sheetChanged() {
    _extent.value = _sheet.size;
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 240), () {
      if (mounted && _extent.value < .78) setState(() => _focusRevision++);
    });
  }

  @override
  void dispose() {
    booking.reviewClosed();
    _mapSelectionWorker?.dispose();
    _focusTimer?.cancel();
    _sheet.removeListener(_sheetChanged);
    _sheet.dispose();
    _extent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final location = booking.location;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: const BookingReviewFooter(),
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _extent,
              builder: (context, extent, _) => Obx(
                () => AppGoogleMap(
                  initialTarget:
                      location.pickup.value ?? const LatLng(15.3694, 44.1910),
                  markers: location.markers,
                  onMapCreated: location.onMapCreated,
                  onTap: location.isChoosingMapPoint.value
                      ? location.selectMapPoint
                      : null,
                  polylines: location.polylines
                      .map(
                        (line) => line.copyWith(colorParam: colors.onSurface),
                      )
                      .toSet(),
                  mapType: location.mapType.value,
                  useModernMapStyle: true,
                  focusBounds: location.hasDrivingRoute
                      ? location.selectedRouteBounds
                      : null,
                  focusBoundsRevision: _focusRevision,
                  focusBoundsPadding: 36,
                  mapPadding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 140,
                    bottom: (constraints.maxHeight * extent)
                        .clamp(
                          0.0,
                          (constraints.maxHeight -
                                  MediaQuery.paddingOf(context).top -
                                  250)
                              .clamp(0.0, double.infinity),
                        )
                        .toDouble(),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: BookingReviewRouteCard(
                    onClose: widget.onClose,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _extent,
              builder: (context, extent, _) => Positioned(
                right: 16,
                bottom: constraints.maxHeight * extent + 12,
                child: Visibility(
                  visible: constraints.maxHeight * (1 - extent) > 200,
                  child: RideIconButton(
                    icon: Icons.near_me_outlined,
                    tooltip: 'review_focus_route'.tr,
                    onPressed: () => setState(() => _focusRevision++),
                  ),
                ),
              ),
            ),
            DraggableScrollableSheet(
              key: const ValueKey('review-services-sheet'),
              controller: _sheet,
              initialChildSize: .62,
              minChildSize: .18,
              maxChildSize: .98,
              snap: true,
              snapSizes: const [.18, .62, .98],
              builder: (context, scrollController) => Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Material(
                    color: colors.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        12,
                        0,
                        12,
                        16,
                      ),
                      children: [
                        Semantics(
                          button: true,
                          label: 'home_expand'.tr,
                          child: InkWell(
                            key: const ValueKey(
                              'review-sheet-handle',
                            ),
                            onTap: () => _sheet.animateTo(
                              _sheet.size > .8 ? .62 : .98,
                              duration: const Duration(
                                milliseconds: 360,
                              ),
                              curve: Curves.easeInOutCubic,
                            ),
                            child: Center(
                              child: Container(
                                width: 38,
                                height: 5,
                                margin: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.outlineVariant,
                                  borderRadius: BorderRadius.circular(
                                    4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const BookingReviewPanel(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingReviewRouteCard extends GetView<BookingController> {
  const BookingReviewRouteCard({required this.onClose, super.key});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _routeRow(
                context,
                field: 0,
                icon: Icons.person_pin_circle_rounded,
                text: controller.location.fromController,
                action: IconButton(
                  tooltip: 'close'.tr,
                  onPressed: controller.ride.bookingLocked ? null : onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ),
              _routeRow(
                context,
                field: 1,
                icon: Icons.flag_rounded,
                text: controller.location.toController,
                action: IconButton(
                  tooltip: 'home_address_details'.tr,
                  onPressed: controller.ride.bookingLocked
                      ? null
                      : () => showBookingArrivalDetails(context),
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
              Obx(
                () => controller.location.isRouteLoading.value
                    ? const LinearProgressIndicator()
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );

  Widget _routeRow(
    BuildContext context, {
    required int field,
    required IconData icon,
    required TextEditingController text,
    required Widget action,
  }) =>
      Row(
        children: [
          const SizedBox(width: 6),
          Icon(icon, size: 25),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => controller.editReviewRoute(field),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: text,
                  builder: (_, value, __) => Text(
                    value.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          if (field == 1)
            Obx(
              () => controller.location.routeDurationSeconds.value <= 0
                  ? const SizedBox.shrink()
                  : Flexible(
                      child: Text(
                        'review_eta'.trParams({
                          'minutes':
                              '${(controller.location.routeDurationSeconds.value / 60).ceil()}',
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
            ),
          action,
        ],
      );
}
