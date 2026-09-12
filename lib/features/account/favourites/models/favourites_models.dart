import 'package:flutter/material.dart';

class FavouritePlace {
  const FavouritePlace(
      {required this.id,
      required this.title,
      required this.address,
      required this.icon,
      this.kind = 'place',
      this.latitude,
      this.longitude});
  final String id;
  final String title;
  final String address;
  final IconData icon;
  final String kind;
  final double? latitude;
  final double? longitude;
}
