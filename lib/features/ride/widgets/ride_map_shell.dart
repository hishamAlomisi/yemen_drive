import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/responsive/app_responsive.dart';
import '../../../shared/widgets/app_google_map.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import 'ride_process_stepper.dart';

class RideMapShell extends StatelessWidget {
  const RideMapShell({
    required this.panel,
    this.panelFooter,
    this.map,
    this.top,
    this.overlay,
    this.foregroundOverlay,
    this.floatingAction,
    this.processBar,
    this.processStep,
    this.processBarTop = 82,
    this.showPanel = true,
    this.bottomNavigationBar,
    this.showRoute = false,
    this.showMarker = true,
    this.fitPanelToContent = false,
    this.panelMaxHeightFactor = .58,
    this.panelHorizontalMargin = 0,
    this.panelBottomMargin = 0,
    this.panelColor,
    this.panelElevation = 12,
    this.embedded = false,
    super.key,
  });

  final Widget panel;
  final Widget? panelFooter;
  final Widget? map;
  final Widget? top;
  final Widget? overlay;
  final Widget? foregroundOverlay;
  final Widget? floatingAction;
  final Widget? processBar;
  final int? processStep;
  final double processBarTop;
  final Widget? bottomNavigationBar;
  final bool showPanel;
  final bool showRoute;
  final bool showMarker;
  final bool fitPanelToContent;
  final double panelMaxHeightFactor;
  final double panelHorizontalMargin;
  final double panelBottomMargin;
  final Color? panelColor;
  final double panelElevation;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        map ??
            _DefaultRideMap(
              showMarker: showMarker,
              showRoute: showRoute,
            ),
        if (overlay != null) Positioned.fill(child: overlay!),
        if (top != null)
          SafeArea(
            bottom: false,
            child: AdaptiveContent(
              padding: context.pagePadding,
              child: top!,
            ),
          ),
        if (processBar != null || processStep != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + processBarTop,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: processBar ??
                      RideProcessStepper(currentStep: processStep!),
                ),
              ),
            ),
          ),
        if (showRoute && Get.isRegistered<LocationController>())
          _RouteMapGuide(
            topOffset: (processBar != null || processStep != null)
                ? processBarTop + 72
                : 12,
          ),
        if (!showPanel)
          const SizedBox.shrink()
        else if (fitPanelToContent)
          _ContentSizedPanel(
            panel: panel,
            panelFooter: panelFooter,
            maxHeightFactor: panelMaxHeightFactor,
            horizontalMargin: panelHorizontalMargin,
            bottomMargin: panelBottomMargin,
            panelColor: panelColor,
            panelElevation: panelElevation,
          )
        else
          _AdaptiveDraggablePanel(
            panel: panel,
            panelFooter: panelFooter,
            maxHeightFactor: panelMaxHeightFactor,
            panelColor: panelColor,
            panelElevation: panelElevation,
          ),
        if (foregroundOverlay != null)
          Positioned.fill(child: foregroundOverlay!),
        if (floatingAction != null)
          Positioned(
            left: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: floatingAction!,
          ),
      ],
    );
    final body = Directionality(
      textDirection: Directionality.of(context),
      child: content,
    );
    if (embedded) return body;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _AdaptiveDraggablePanel extends StatefulWidget {
  const _AdaptiveDraggablePanel({
    required this.panel,
    required this.panelFooter,
    required this.maxHeightFactor,
    required this.panelColor,
    required this.panelElevation,
  });

  final Widget panel;
  final Widget? panelFooter;
  final double maxHeightFactor;
  final Color? panelColor;
  final double panelElevation;

  @override
  State<_AdaptiveDraggablePanel> createState() =>
      _AdaptiveDraggablePanelState();
}

class _AdaptiveDraggablePanelState extends State<_AdaptiveDraggablePanel> {
  static const double _minHeightFactor = .14;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double? _lastTarget;

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _fitToContent(Size size) {
    if (!_sheetController.isAttached || !mounted) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final footerHeight = widget.panelFooter == null ? 0.0 : 76.0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final naturalHeight = size.height + 26 + footerHeight + safeBottom;
    final target = (naturalHeight / screenHeight)
        .clamp(_minHeightFactor, widget.maxHeightFactor)
        .toDouble();
    if (_lastTarget != null && (_lastTarget! - target).abs() < .01) return;
    _lastTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sheetController.isAttached) return;
      _sheetController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: widget.maxHeightFactor,
        minChildSize: _minHeightFactor,
        maxChildSize: widget.maxHeightFactor,
        snap: true,
        snapSizes: <double>[_minHeightFactor, widget.maxHeightFactor],
        builder: (context, scrollController) => _PanelSurface(
          panel: widget.panel,
          panelFooter: widget.panelFooter,
          scrollController: scrollController,
          expandContent: true,
          onPanelSizeChanged: _fitToContent,
          panelColor: widget.panelColor,
          panelElevation: widget.panelElevation,
        ),
      );
}

class _ContentSizedPanel extends StatelessWidget {
  const _ContentSizedPanel({
    required this.panel,
    required this.panelFooter,
    required this.maxHeightFactor,
    required this.horizontalMargin,
    required this.bottomMargin,
    required this.panelColor,
    required this.panelElevation,
  });

  final Widget panel;
  final Widget? panelFooter;
  final double maxHeightFactor;
  final double horizontalMargin;
  final double bottomMargin;
  final Color? panelColor;
  final double panelElevation;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalMargin,
            0,
            horizontalMargin,
            bottomMargin,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppBreakpoints.maxContent,
              maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
            ),
            child: _PanelSurface(
              panel: panel,
              panelFooter: panelFooter,
              expandContent: false,
              panelColor: panelColor,
              panelElevation: panelElevation,
            ),
          ),
        ),
      );
}

class _PanelSurface extends StatelessWidget {
  const _PanelSurface({
    required this.panel,
    required this.panelFooter,
    required this.expandContent,
    required this.panelColor,
    required this.panelElevation,
    this.scrollController,
    this.onPanelSizeChanged,
  });

  final Widget panel;
  final Widget? panelFooter;
  final bool expandContent;
  final Color? panelColor;
  final double panelElevation;
  final ScrollController? scrollController;
  final ValueChanged<Size>? onPanelSizeChanged;

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        ResponsiveContext(context).responsiveValue(phone: 16, tablet: 28),
        10,
        ResponsiveContext(context).responsiveValue(phone: 16, tablet: 28),
        panelFooter == null ? AppSpacing.md : AppSpacing.sm,
      ),
      child: _SizeReporter(
        onSizeChanged: onPanelSizeChanged,
        child: panel,
      ),
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
        child: Material(
          color: panelColor ?? Theme.of(context).colorScheme.surface,
          elevation: panelElevation,
          shadowColor: Colors.black26,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
              children: <Widget>[
                if (expandContent)
                  Expanded(child: content)
                else
                  Flexible(child: content),
                if (panelFooter != null)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveContext(context)
                          .responsiveValue(phone: 16, tablet: 28),
                      AppSpacing.sm,
                      ResponsiveContext(context)
                          .responsiveValue(phone: 16, tablet: 28),
                      AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: .35),
                        ),
                      ),
                    ),
                    child: panelFooter,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required Widget child, this.onSizeChanged})
      : super(child: child);

  final ValueChanged<Size>? onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SizeReporterRenderObject(onSizeChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _SizeReporterRenderObject renderObject,
  ) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _SizeReporterRenderObject extends RenderProxyBox {
  _SizeReporterRenderObject(this.onSizeChanged);

  ValueChanged<Size>? onSizeChanged;
  Size? _previousSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _previousSize) return;
    _previousSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSizeChanged?.call(size);
    });
  }
}

class _DefaultRideMap extends StatelessWidget {
  const _DefaultRideMap({required this.showMarker, required this.showRoute});

  final bool showMarker;
  final bool showRoute;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<LocationController>()) {
      return AppGoogleMap(
        showDemoMarker: showMarker,
        showDemoRoute: showRoute,
      );
    }
    final controller = Get.find<LocationController>();
    return Obx(
      () => AppGoogleMap(
        markers: showMarker || showRoute ? controller.markers : const {},
        polylines: showRoute ? controller.polylines : const {},
        focusBounds: showRoute ? controller.selectedRouteBounds : null,
        focusBoundsPadding: 104,
        showDemoMarker: showMarker,
        showDemoRoute: showRoute,
      ),
    );
  }
}

class _RouteMapGuide extends StatelessWidget {
  const _RouteMapGuide({required this.topOffset});

  final double topOffset;

  @override
  Widget build(BuildContext context) {
    final location = Get.find<LocationController>();
    return PositionedDirectional(
      top: MediaQuery.paddingOf(context).top + topOffset,
      end: 16,
      child: SafeArea(
        bottom: false,
        child: Obx(() {
          if (!location.hasCompleteRoute) return const SizedBox.shrink();
          final kilometers = location.routeDistanceMeters.value / 1000;
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Material(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: .94),
              elevation: 5,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _GuidePlaceRow(
                      icon: Icons.trip_origin_rounded,
                      color: AppColors.primaryDark,
                      label: location.fromController.text.trim().isEmpty
                          ? 'نقطة الانطلاق'
                          : location.fromController.text.trim(),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 10),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 2,
                            height: 12,
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: .55),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            kilometers > 0
                                ? '${kilometers.toStringAsFixed(1)} كم'
                                : 'جار حساب المسافة',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    _GuidePlaceRow(
                      icon: Icons.location_on_rounded,
                      color: AppColors.secondary,
                      label: location.toController.text.trim().isEmpty
                          ? 'الوجهة'
                          : location.toController.text.trim(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _GuidePlaceRow extends StatelessWidget {
  const _GuidePlaceRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      );
}

class RidePanelHandle extends StatelessWidget {
  const RidePanelHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 48,
          height: 5,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      );
}
