class RideHomeService {
  const RideHomeService(
      {this.id,
      required this.code,
      required this.name,
      this.imageUrl,
      this.rideServiceType,
      this.sortOrder = 0});
  final int? id;
  final String code;
  final String name;
  final String? imageUrl;
  final String? rideServiceType;
  final int sortOrder;
}

const demoHomeServices = <RideHomeService>[
  RideHomeService(
      code: 'transport',
      name: 'نقل',
      imageUrl: 'assets/images/services/transport.png',
      rideServiceType: 'transport'),
  RideHomeService(
      code: 'delivery',
      name: 'توصيل',
      imageUrl: 'assets/images/services/delivery.png',
      rideServiceType: 'delivery'),
  RideHomeService(
      code: 'rental',
      name: 'تأجير',
      imageUrl: 'assets/images/services/rental.png'),
  RideHomeService(
      code: 'scheduled',
      name: 'رحلات مجدولة',
      imageUrl: 'assets/images/services/scheduled.png'),
];
