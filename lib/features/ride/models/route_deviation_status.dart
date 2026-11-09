class RouteDeviationStatus {
  const RouteDeviationStatus({
    required this.available,
    required this.isDeviating,
    required this.distanceMeters,
    required this.direction,
    required this.routeVersion,
    this.accepted = false,
    this.message = '',
  });

  factory RouteDeviationStatus.fromJson(Map<Object?, Object?> data) =>
      RouteDeviationStatus(
        available: data['available'] == true,
        isDeviating: data['isDeviating'] == true,
        distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
        direction: '${data['direction'] ?? ''}',
        routeVersion: '${data['routeVersion'] ?? ''}',
        accepted: data['accepted'] == true,
        message: '${data['message'] ?? ''}',
      );

  final bool available;
  final bool isDeviating;
  final double distanceMeters;
  final String direction;
  final String routeVersion;
  final bool accepted;
  final String message;

  String get description =>
      'السائق بعيد عن مسار الرحلة بمسافة ${distanceMeters.round()} متر'
      '${direction.isEmpty ? '' : ' باتجاه $direction'}. هل يمر السائق في مسار آمن؟';
}

/// A rider's decision silences the current deviation episode. A fresh route
/// version or two confirmed returns to the road allows a new warning.
class RouteDeviationPromptPolicy {
  String? _scope;
  bool _handled = false;
  int _onRouteSamples = 0;

  void reset() {
    _scope = null;
    _handled = false;
    _onRouteSamples = 0;
  }

  bool shouldPrompt(String rideId, RouteDeviationStatus status) {
    if (!status.available) return false;
    final scope = '$rideId:${status.routeVersion}';
    if (_scope != scope) {
      reset();
      _scope = scope;
    }
    if (!status.isDeviating) {
      if (++_onRouteSamples >= 2) _handled = false;
      return false;
    }
    _onRouteSamples = 0;
    return !_handled;
  }

  void handled() => _handled = true;
}
