enum RideHistoryStatus { upcoming, completed, cancelled }

class RideHistoryItem {
  const RideHistoryItem(
      {required this.id,
      required this.pickup,
      required this.destination,
      required this.date,
      required this.amount,
      required this.status,
      required this.totalDue,
      required this.cancellationFee,
      required this.isCashPaid,
      this.serviceKindName,
      this.serviceName,
      this.driverId});
  final String id;
  final String pickup;
  final String destination;
  final DateTime date;
  final double amount;
  final RideHistoryStatus status;
  final double totalDue;
  final double cancellationFee;
  final bool isCashPaid;
  final String? serviceKindName;
  final String? serviceName;
  final String? driverId;
}
