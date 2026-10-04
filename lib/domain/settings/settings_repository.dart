import 'package:billzo/domain/settings/app_settings.dart';

/// Abstract contract for device-local application settings repository.
abstract class ISettingsRepository {
  /// Loads all local application settings.
  Future<AppSettings> getSettings();

  /// Updates all local application settings.
  Future<void> saveSettings(AppSettings settings);

  /// Gets a specific raw setting by string key.
  Future<String?> getSetting(String key);

  /// Sets a specific raw setting by string key.
  Future<void> setSetting(String key, String value);
}
