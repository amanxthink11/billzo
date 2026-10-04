/// Strongly-typed device-local application settings.
class AppSettings {
  final String? activeBusinessId;
  final String themeMode; // 'system', 'light', 'dark'
  final bool onboardingCompleted;
  final String fiscalYear;
  final DateTime? lastBackupCheck;

  const AppSettings({
    this.activeBusinessId,
    this.themeMode = 'light',
    this.onboardingCompleted = false,
    this.fiscalYear = '2026-2027',
    this.lastBackupCheck,
  });

  AppSettings copyWith({
    String? activeBusinessId,
    String? themeMode,
    bool? onboardingCompleted,
    String? fiscalYear,
    DateTime? lastBackupCheck,
  }) {
    return AppSettings(
      activeBusinessId: activeBusinessId ?? this.activeBusinessId,
      themeMode: themeMode ?? this.themeMode,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      fiscalYear: fiscalYear ?? this.fiscalYear,
      lastBackupCheck: lastBackupCheck ?? this.lastBackupCheck,
    );
  }
}
