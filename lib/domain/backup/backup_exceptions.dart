/// Base exception for all Billzo backup and restore operations.
class BackupException implements Exception {
  final String message;
  final dynamic cause;

  const BackupException(this.message, [this.cause]);

  @override
  String toString() => cause != null ? '$message (Cause: $cause)' : message;
}

/// Thrown when a backup package or its database fails cryptographic checksum validation.
class BackupCorruptedException extends BackupException {
  const BackupCorruptedException(super.message, [super.cause]);
}

/// Thrown when a backup package is structurally invalid or missing required contents.
class InvalidBackupException extends BackupException {
  const InvalidBackupException(super.message, [super.cause]);
}

/// Thrown when the format_version of a backup package is unsupported by this version of Billzo.
class UnsupportedBackupVersionException extends BackupException {
  const UnsupportedBackupVersionException(super.message, [super.cause]);
}

/// Thrown when a backup was created with a newer database schema than the current application supports.
class IncompatibleSchemaException extends BackupException {
  const IncompatibleSchemaException(super.message, [super.cause]);
}

/// Thrown when attempting to restore a backup belonging to another business without authorization.
class CrossBusinessRestoreMismatchException extends BackupException {
  final String backupBusinessId;
  final String currentBusinessId;

  const CrossBusinessRestoreMismatchException({
    required this.backupBusinessId,
    required this.currentBusinessId,
    String? message,
  }) : super(message ?? 'Backup business ($backupBusinessId) does not match the active business ($currentBusinessId).');
}

/// Thrown when the mandatory pre-restore safety snapshot cannot be created.
class PreRestoreSafetyBackupFailedException extends BackupException {
  const PreRestoreSafetyBackupFailedException(super.message, [super.cause]);
}

/// Thrown when the restore execution fails. Includes rollback state confirmation.
class RestoreFailedException extends BackupException {
  final bool rolledBackSuccessfully;
  final String? safetySnapshotPath;

  const RestoreFailedException(
    String message, {
    this.rolledBackSuccessfully = false,
    this.safetySnapshotPath,
    dynamic cause,
  }) : super(message, cause);

  @override
  String toString() {
    final rollbackNote = rolledBackSuccessfully
        ? ' [Safe Rollback: Your database was restored to its previous state from $safetySnapshotPath]'
        : ' [CRITICAL: Automatic rollback failed. Safety backup located at $safetySnapshotPath]';
    return '$message$rollbackNote';
  }
}

