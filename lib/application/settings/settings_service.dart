import 'package:billzo/domain/settings/app_settings.dart';
import 'package:billzo/domain/settings/settings_repository.dart';

/// Application service orchestrating device-local application settings.
class SettingsService {
  final ISettingsRepository _repository;

  SettingsService(this._repository);

  Future<AppSettings> getSettings() async {
    return await _repository.getSettings();
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _repository.saveSettings(settings);
  }

  Future<void> updateThemeMode(String themeMode) async {
    final current = await _repository.getSettings();
    await _repository.saveSettings(current.copyWith(themeMode: themeMode));
  }

  Future<void> markOnboardingCompleted() async {
    final current = await _repository.getSettings();
    await _repository.saveSettings(current.copyWith(onboardingCompleted: true));
  }
}
