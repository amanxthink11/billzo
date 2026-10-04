import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/domain/settings/app_settings.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final service = ref.watch(settingsServiceProvider);
    return await service.getSettings();
  }

  Future<void> updateSettings(AppSettings settings) async {
    final service = ref.read(settingsServiceProvider);
    await service.saveSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> setThemeMode(String mode) async {
    final service = ref.read(settingsServiceProvider);
    await service.updateThemeMode(mode);
    final current = state.asData?.value ?? const AppSettings();
    state = AsyncValue.data(current.copyWith(themeMode: mode));
  }
}

final appSettingsStateProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(() {
  return AppSettingsNotifier();
});
