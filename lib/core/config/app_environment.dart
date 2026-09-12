import '../../features/account/models/account_models.dart';

class AppEnvironment {
  AppEnvironment._();

  static late final String flavor;
  static late final String baseUrl;
  static String defaultCurrency = 'ر.ي';
  static bool useDemoData = true;
  static String googleMapsApiKey = '';
  static String googleRoutesApiKey = '';
  static String googleGeocodingApiKey = '';
  static String googlePlacesApiKey = '';
  static String androidPackageName = 'com.example.yemen_drive';
  static String androidCertSha1 = '';
  static String signalRHubUrl = '';
  static bool _isConfigured = false;

  static bool get isConfigured => _isConfigured;
  static bool get isProduction => flavor == 'prod';
  static List<PaymentMethodItem> paymentMethods = <PaymentMethodItem>[];

  static void configure({
    required String flavor,
    required String baseUrl,
    bool useDemoData = true,
    String googleMapsApiKey = '',
    String googleRoutesApiKey = '',
    String googleGeocodingApiKey = '',
    String googlePlacesApiKey = '',
    String androidPackageName = 'com.example.yemen_drive',
    String androidCertSha1 = '',
    String signalRHubUrl = '',
  }) {
    AppEnvironment.flavor = flavor;
    AppEnvironment.baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    AppEnvironment.useDemoData = useDemoData;
    AppEnvironment.googleMapsApiKey = googleMapsApiKey;
    AppEnvironment.googleRoutesApiKey =
        googleRoutesApiKey.isEmpty ? googleMapsApiKey : googleRoutesApiKey;
    AppEnvironment.googleGeocodingApiKey = googleGeocodingApiKey.isEmpty
        ? googleMapsApiKey
        : googleGeocodingApiKey;
    AppEnvironment.googlePlacesApiKey =
        googlePlacesApiKey.isEmpty ? googleMapsApiKey : googlePlacesApiKey;
    AppEnvironment.androidPackageName = androidPackageName;
    AppEnvironment.androidCertSha1 = androidCertSha1.replaceAll(':', '');
    AppEnvironment.signalRHubUrl = signalRHubUrl.isEmpty
        ? _defaultSignalRHubUrl(AppEnvironment.baseUrl)
        : signalRHubUrl;
    _isConfigured = true;
  }

  static String _defaultSignalRHubUrl(String apiBaseUrl) {
    // The API controllers are under /api, while the actual Hub is mapped at
    // the host root (/hubs/tracking).
    final root = apiBaseUrl.replaceFirst(
      RegExp(r'/api(?:/v[0-9]+)?/?$', caseSensitive: false),
      '',
    );
    return '$root/hubs/tracking';
  }
}
