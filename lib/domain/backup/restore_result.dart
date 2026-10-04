import 'package:billzo/domain/backup/backup_manifest.dart';

/// Encapsulates the verified outcome of a successfully executed restore operation.
class RestoreResult {
  /// The verified manifest extracted from the restored backup package.
  final BackupManifest manifest;

  /// The absolute filesystem path to the pre-restore safety snapshot created before the hot-swap.
  final String safetySnapshotPath;

  /// The exact timestamp when restoration completed.
  final DateTime restoredAt;

  /// Total count of media assets (logos, signatures) restored into local application storage.
  final int restoredMediaFilesCount;

  const RestoreResult({
    required this.manifest,
    required this.safetySnapshotPath,
    required this.restoredAt,
    this.restoredMediaFilesCount = 0,
  });

  @override
  String toString() {
    return 'RestoreResult(business: ${manifest.businessName}, restoredAt: $restoredAt, mediaFiles: $restoredMediaFilesCount, safetyBackup: $safetySnapshotPath)';
  }
}
