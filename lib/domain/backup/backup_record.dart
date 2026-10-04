/// Entity representing a persisted backup entry in the local `backup_records` database table.
class BackupRecord {
  final String id;
  final String businessId;
  final String filePath;
  final int fileSizeBytes;
  final String sha256Checksum;
  final String backupType; // 'MANUAL', 'AUTO', 'SAFETY'
  final int databaseVersion;
  final DateTime createdAt;
  final String status; // 'VALIDATED', 'FAILED', 'PENDING'

  const BackupRecord({
    required this.id,
    required this.businessId,
    required this.filePath,
    required this.fileSizeBytes,
    required this.sha256Checksum,
    required this.backupType,
    required this.databaseVersion,
    required this.createdAt,
    this.status = 'VALIDATED',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'file_path': filePath,
      'file_size_bytes': fileSizeBytes,
      'sha256_checksum': sha256Checksum.toLowerCase(),
      'backup_type': backupType,
      'database_version': databaseVersion,
      'created_at': createdAt.toUtc().toIso8601String(),
      'status': status,
    };
  }

  factory BackupRecord.fromMap(Map<String, dynamic> map) {
    return BackupRecord(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      filePath: map['file_path'] as String,
      fileSizeBytes: map['file_size_bytes'] as int,
      sha256Checksum: (map['sha256_checksum'] as String).toLowerCase(),
      backupType: map['backup_type'] as String,
      databaseVersion: map['database_version'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: map['status'] as String? ?? 'VALIDATED',
    );
  }

  BackupRecord copyWith({
    String? id,
    String? businessId,
    String? filePath,
    int? fileSizeBytes,
    String? sha256Checksum,
    String? backupType,
    int? databaseVersion,
    DateTime? createdAt,
    String? status,
  }) {
    return BackupRecord(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      filePath: filePath ?? this.filePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      sha256Checksum: sha256Checksum ?? this.sha256Checksum,
      backupType: backupType ?? this.backupType,
      databaseVersion: databaseVersion ?? this.databaseVersion,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
