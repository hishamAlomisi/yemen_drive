abstract final class ApiEndpoints {
  static const String execute = 'execute';
  // Matches YemenDrive.Api.Controllers.AuthController.
  static const String signIn = 'auth/login';
  // The API exposes registration at POST /api/auth/register.
  static const String signUp = 'auth/register';
  static const String refresh = 'auth/refresh';
  static const String profile = 'users/me';
  static const String rides = 'rides';
  static const String rideQuotes = 'rides/quotes';
  static const String pricingQuote = 'pricing/quote';
  // Catalog endpoint backed by the admin-managed service records.
  static const String vehicles = 'services';
  static const String serviceKinds = 'service-kinds';
  static const String wallet = 'wallet';
  static const String payments = 'payments';
  static const String notifications = 'notifications';
}
