import 'package:flutter/material.dart';

const savedPlaceKinds = <String, String>{
  'home': 'المنزل',
  'work': 'العمل',
  'park': 'الحديقة',
  'mall': 'المول',
  'market': 'السوق'
};
IconData savedPlaceIcon(String kind) => switch (kind) {
      'home' => Icons.home_rounded,
      'work' => Icons.work_rounded,
      'park' => Icons.park_rounded,
      'mall' => Icons.shopping_bag_rounded,
      'market' => Icons.storefront_rounded,
      'airport' => Icons.flight_rounded,
      _ => Icons.place_rounded,
    };
bool validSavedCoordinates(double? lat, double? lng) =>
    lat != null &&
    lng != null &&
    lat.isFinite &&
    lng.isFinite &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180 &&
    !(lat == 0 && lng == 0);
