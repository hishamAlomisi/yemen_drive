/// A destination selected for a quote. This never changes the active ride.
class RideRouteDestination {
  const RideRouteDestination({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      label.trim().isNotEmpty;
}

/// Validated, server-owned pricing and permissions for a route change.
class RideRouteChangeSnapshot {
  RideRouteChangeSnapshot(Object? raw, {required int expectedRideId}) {
    final data = objectMap(raw);
    rideId = integer(data, 'rideId');
    if (rideId != expectedRideId || rideId <= 0) invalid();
    serverNowUtc = date(data['serverNowUtc']) ?? invalid();
    routeVersion = integer(data, 'routeVersion');
    canRequest = boolean(data, 'canRequest');
    unavailableReason = data['unavailableReason']?.toString();
    request = data['request'] == null
        ? null
        : RideRouteChangeRequest(objectMap(data['request']));
    final entries = data['history'];
    if (entries is! List) invalid();
    history = List.unmodifiable(
      entries.map((raw) => RideRouteChangeRequest(objectMap(raw))),
    );
  }

  late final int rideId;
  late final DateTime serverNowUtc;
  late final int routeVersion;
  late final bool canRequest;
  late final String? unavailableReason;
  late final RideRouteChangeRequest? request;
  late final List<RideRouteChangeRequest> history;

  static Never invalid() => throw const FormatException(
        'تعذرت قراءة عرض تغيير الوجهة. حدّث الحالة وحاول مجددًا.',
      );

  static Map<String, Object?> objectMap(Object? value) {
    if (value is! Map) invalid();
    return Map<String, Object?>.from(value);
  }

  static double number(
    Map<String, Object?> data,
    String field, {
    bool signed = false,
  }) {
    final raw = data[field];
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (value == null || !value.isFinite || (!signed && value < 0)) invalid();
    return value;
  }

  static int integer(Map<String, Object?> data, String field) {
    final value = number(data, field);
    if (value != value.truncateToDouble()) invalid();
    return value.toInt();
  }

  static bool boolean(Map<String, Object?> data, String field) {
    final value = data[field];
    if (value is! bool) invalid();
    return value;
  }

  static DateTime? date(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(
      raw.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw)
          ? raw
          : '${raw}Z',
    )?.toUtc();
  }
}

class RideRouteChangeRequest {
  RideRouteChangeRequest(Map<String, Object?> data) {
    id = RideRouteChangeSnapshot.integer(data, 'id');
    status = '${data['status']}';
    if (id <= 0 ||
        !const {
          'quoted',
          'pending',
          'accepted',
          'rejected',
          'cancelled',
          'expired',
        }.contains(status)) {
      RideRouteChangeSnapshot.invalid();
    }
    requestedByMe = RideRouteChangeSnapshot.boolean(data, 'requestedByMe');
    canConfirm = RideRouteChangeSnapshot.boolean(data, 'canConfirm');
    canDecide = RideRouteChangeSnapshot.boolean(data, 'canDecide');
    expiresAtUtc = RideRouteChangeSnapshot.date(data['expiresAtUtc']);
    if (isOpen && expiresAtUtc == null) RideRouteChangeSnapshot.invalid();
    destination = RideRouteDestination(
      latitude: RideRouteChangeSnapshot.number(
        data,
        'newDestinationLatitude',
        signed: true,
      ),
      longitude: RideRouteChangeSnapshot.number(
        data,
        'newDestinationLongitude',
        signed: true,
      ),
      label: '${data['newDestinationLabel'] ?? ''}',
    );
    if (!destination.isValid) RideRouteChangeSnapshot.invalid();
    invoice = RideRouteChangeInvoice(
      RideRouteChangeSnapshot.objectMap(data['invoice']),
    );
  }

  late final int id;
  late final String status;
  late final bool requestedByMe;
  late final bool canConfirm;
  late final bool canDecide;
  late final DateTime? expiresAtUtc;
  late final RideRouteDestination destination;
  late final RideRouteChangeInvoice invoice;
  bool get isOpen => status == 'quoted' || status == 'pending';
  bool isExpired(DateTime now) => isOpen && !now.isBefore(expiresAtUtc!);
}

class RideRouteChangeInvoice {
  RideRouteChangeInvoice(Map<String, Object?> data)
      : values = Map.unmodifiable({
          for (final field in fields)
            field: RideRouteChangeSnapshot.number(
              data,
              field,
              signed: field == 'difference',
            ),
        });

  static const fields = <String>[
    'previousTotal',
    'completedDistanceMeters',
    'completedFare',
    'originalServiceFee',
    'routeChangeFee',
    'previousRouteChangeFees',
    'newDistanceMeters',
    'newDurationSeconds',
    'newRouteFare',
    'waitingFee',
    'newTotal',
    'difference',
  ];
  final Map<String, double> values;
  double operator [](String field) => values[field]!;
  String get fingerprint => fields.map((field) => values[field]).join('|');
}
