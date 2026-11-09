import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A frozen route snapshot that the map plugin can share between marker frames.
///
/// The plugin clones every polyline when diffing its objects. Ordinary polylines
/// copy all vertices each time, even when only a vehicle marker moved. Freezing
/// both lists lets those snapshots safely reuse this object and makes unchanged
/// geometry comparisons use the same lists. Create a new snapshot after GPS
/// progress or a confirmed route change; never mutate a published route.
final class LiveRoutePolyline extends Polyline {
  LiveRoutePolyline({
    required super.polylineId,
    super.consumeTapEvents,
    super.color,
    super.endCap,
    super.geodesic,
    super.jointType,
    List<LatLng> points = const <LatLng>[],
    List<PatternItem> patterns = const <PatternItem>[],
    super.startCap,
    super.visible,
    super.width,
    super.zIndex,
    super.onTap,
  }) : super(
          points: List<LatLng>.unmodifiable(points),
          patterns: List<PatternItem>.unmodifiable(patterns),
        );

  factory LiveRoutePolyline.from(Polyline source) => LiveRoutePolyline(
        polylineId: source.polylineId,
        consumeTapEvents: source.consumeTapEvents,
        color: source.color,
        endCap: source.endCap,
        geodesic: source.geodesic,
        jointType: source.jointType,
        points: source.points,
        patterns: source.patterns,
        startCap: source.startCap,
        visible: source.visible,
        width: source.width,
        zIndex: source.zIndex,
        onTap: source.onTap,
      );

  @override
  LiveRoutePolyline clone() => this;

  @override
  LiveRoutePolyline copyWith({
    Color? colorParam,
    bool? consumeTapEventsParam,
    Cap? endCapParam,
    bool? geodesicParam,
    JointType? jointTypeParam,
    List<PatternItem>? patternsParam,
    List<LatLng>? pointsParam,
    Cap? startCapParam,
    bool? visibleParam,
    int? widthParam,
    int? zIndexParam,
    VoidCallback? onTapParam,
  }) =>
      LiveRoutePolyline(
        polylineId: polylineId,
        consumeTapEvents: consumeTapEventsParam ?? consumeTapEvents,
        color: colorParam ?? color,
        endCap: endCapParam ?? endCap,
        geodesic: geodesicParam ?? geodesic,
        jointType: jointTypeParam ?? jointType,
        points: pointsParam ?? points,
        patterns: patternsParam ?? patterns,
        startCap: startCapParam ?? startCap,
        visible: visibleParam ?? visible,
        width: widthParam ?? width,
        zIndex: zIndexParam ?? zIndex,
        onTap: onTapParam ?? onTap,
      );
}
