class RideOffer {
  const RideOffer(
      {required this.id,
      required this.title,
      required this.discount,
      required this.code,
      required this.description,
      required this.expiryLabel,
      this.isClaimed = false});
  final String id;
  final String title;
  final String discount;
  final String code;
  final String description;
  final String expiryLabel;
  final bool isClaimed;
}
