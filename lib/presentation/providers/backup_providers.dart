import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/application/backup/restore_service.dart';
import 'package:billzo/domain/backup/backup_record.dart';
import 'package:billzo/domain/backup/backup_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_backup_repository.dart';
import 'package:billzo/infrastructure/services/backup/backup_service.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Provider for [IBackupRepository].
final backupRepositoryProvider = Provider<IBackupRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteBackupRepository(dbHelper: dbHelper);
});

/// Provider for [IBackupService].
final backupServiceProvider = Provider<IBackupService>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  final paths = ref.watch(pathProvider);
  final repo = ref.watch(backupRepositoryProvider);
  return BackupService(
    dbHelper: dbHelper,
    pathProvider: paths,
    backupRepository: repo,
  );
});

/// Provider for [IRestoreService].
final restoreServiceProvider = Provider<IRestoreService>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  final paths = ref.watch(pathProvider);
  return RestoreService(
    dbHelper: dbHelper,
    pathProvider: paths,
  );
});

/// Provider fetching backup history records from database for a specific business.
final backupHistoryProvider = FutureProvider.family<List<BackupRecord>, String>((ref, businessId) async {
  final repository = ref.watch(backupRepositoryProvider);
  return repository.getBackupHistory(businessId);
});

/// Provider listing all physical `.billzobak` files discovered in the local backups folder.
final localBackupFilesProvider = FutureProvider<List<File>>((ref) async {
  final backupService = ref.watch(backupServiceProvider);
  return backupService.getLocalBackupFiles();
});
