import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_environment.dart';
import 'map_backdrop.dart';

class AppGoogleMap extends StatefulWidget {
  const AppGoogleMap({
    this.width,
    this.height,
    this.initialTarget = const LatLng(15.3694, 44.1910),
    this.initialZoom = 14,
    this.followTarget,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.myLocationEnabled = false,
    this.zoomControlsEnabled = false,
    this.compassEnabled = true,
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
    this.lightStyle,
    this.darkStyle,
    this.showDemoMarker = true,
    this.showDemoRoute = false,
    super.key,
  });

  final double? width;
  final double? height;
  final LatLng initialTarget;
  final double initialZoom;
  final LatLng? followTarget;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final bool myLocationEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;
  final MapCreatedCallback? onMapCreated;
  final CameraPositionCallback? onCameraMove;
  final VoidCallback? onCameraIdle;
  final ArgumentCallback<LatLng>? onTap;
  final String? lightStyle;
  final String? darkStyle;
  final bool showDemoMarker;
  final bool showDemoRoute;

  @override
  State<AppGoogleMap> createState() => _AppGoogleMapState();
}

class _AppGoogleMapState extends State<AppGoogleMap> {
  bool _isLoading = true;
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(covariant AppGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.followTarget;
    if (target != null && target != oldWidget.followTarget) {
      _controller?.animateCamera(CameraUpdate.newLatLng(target));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Android and iOS receive the key through their native configuration.
    // Web needs its JavaScript API key during web bootstrap.
    if (kIsWeb && AppEnvironment.googleMapsApiKey.isEmpty) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: MapBackdrop(
          showMarker: widget.showDemoMarker,
          showRoute: widget.showDemoRoute,
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialTarget,
              zoom: widget.initialZoom,
            ),
            markers: widget.markers,
            polylines: widget.polylines,
            myLocationEnabled: widget.myLocationEnabled,
            myLocationButtonEnabled: widget.myLocationEnabled,
            zoomControlsEnabled: widget.zoomControlsEnabled,
            compassEnabled: widget.compassEnabled,
            onMapCreated: (controller) {
              _controller = controller;
              final style = isDark ? widget.darkStyle : widget.lightStyle;
              if (style != null && style.isNotEmpty) {
                controller.setMapStyle(style);
              }
              widget.onMapCreated?.call(controller);
              if (mounted) setState(() => _isLoading = false);
            },
            onCameraMove: widget.onCameraMove,
            onCameraIdle: widget.onCameraIdle,
            onTap: widget.onTap,
          ),
          if (_isLoading)
            IgnorePointer(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor.withValues(
                      alpha: .82,
                    ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 10),
                      Text('map_loading'.tr),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
