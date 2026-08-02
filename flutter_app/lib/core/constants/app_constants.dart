class AppConstants {
  AppConstants._();

  static const String appName = 'Sahjanand';
  static const String appTagline = 'सहजानन्द : विश्वासानन्द :';

  // API base URLs
  static const String devBaseUrl = 'http://10.0.2.2:8000';   // Android emulator → localhost
  static const String prodBaseUrl = 'https://sahjanand-api.onrender.com';

  // Use prodBaseUrl when running on real device / release build
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: devBaseUrl,
  );

  // Secure storage keys
  static const String tokenKey = 'sahjanand_token';
  static const String userKey  = 'sahjanand_user';

  // Route names
  static const String routeLogin          = '/login';
  static const String routeForgotPassword = '/forgot-password';
  static const String routeDashboard      = '/dashboard';
  static const String routeSales          = '/sales';
  static const String routeReminders      = '/reminders';
  static const String routeSamples        = '/samples';
}
