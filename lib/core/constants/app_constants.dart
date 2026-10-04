/// Global application constants for Billzo.
class AppConstants {
  AppConstants._();

  static const String appName = 'Billzo';
  static const String appTagline = 'Billing. Business. Simple.';
  static const String appVersion = '1.0.1';
  static const int appBuildNumber = 2;

  // Desktop Window Dimensions
  static const double minWindowWidth = 1024;
  static const double minWindowHeight = 700;
  static const double defaultWindowWidth = 1280;
  static const double defaultWindowHeight = 800;

  // Currency & Locale Defaults
  static const String defaultCurrencyCode = 'INR';
  static const String defaultCurrencySymbol = '₹';
  static const String defaultCountry = 'India';

  // Indian GST Default Rates (in basis points)
  static const int gstRate0 = 0;
  static const int gstRate5 = 500;
  static const int gstRate12 = 1200;
  static const int gstRate18 = 1800;
  static const int gstRate28 = 2800;

  // Database Configurations
  static const String databaseFileName = 'billzo.db';
  static const int currentSchemaVersion = 6;

  // Backup & Restore Configurations
  static const int backupFormatVersion = 1;
  static const String backupFileExtension = '.billzobak';
}

