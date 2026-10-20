class RideHomeService {
  const RideHomeService(
      {this.id,
      required this.code,
      required this.name,
      this.imageUrl,
      this.description,
      this.rideServiceType,
      this.isDefault = false,
      this.sortOrder = 0});
  final int? id;
  final String code;
  final String name;
  final String? imageUrl;
  final String? description;
  final String? rideServiceType;
  final bool isDefault;
  final int sortOrder;
}
