import 'dart:convert';

/// Represents the cryptographic metadata manifest (`manifest.json`) contained
/// within every `.billzobak` backup package.
class BackupManifest {
  /// Format version of the backup archive container itself (Specification v1).
  final int formatVersion;

  /// Application version that produced this backup.
  final String appVersion;

  /// Application build number.
  final int appBuildNumber;

  /// The SQLite database schema version of the backed-up database.
  final int schemaVersion;

  /// UTC ISO-8601 timestamp when this backup was created.
  final DateTime createdAt;

  /// Identifier of the business organization owning the backed-up dataset.
  final String businessId;

  /// Display/trade name of the business organization.
  final String businessName;

  /// Lowercase hexadecimal SHA-256 hash of the `database.sqlite` file.
  final String databaseSha256;

  /// Count of non-deleted sales invoices in the database snapshot.
  final int totalInvoices;

  /// Count of non-deleted customer parties in the database snapshot.
  final int totalCustomers;

  /// Count of non-deleted catalog products in the database snapshot.
  final int totalProducts;

  /// Origin type: 'MANUAL', 'AUTO', or 'SAFETY'.
  final String backupType;

  const BackupManifest({
    this.formatVersion = 1,
    required this.appVersion,
    required this.appBuildNumber,
    required this.schemaVersion,
    required this.createdAt,
    required this.businessId,
    required this.businessName,
    required this.databaseSha256,
    this.totalInvoices = 0,
    this.totalCustomers = 0,
    this.totalProducts = 0,
    this.backupType = 'MANUAL',
  });

  Map<String, dynamic> toMap() {
    return {
      'format_version': formatVersion,
      'app_version': appVersion,
      'app_build_number': appBuildNumber,
      'schema_version': schemaVersion,
      'created_at': createdAt.toUtc().toIso8601String(),
      'business_id': businessId,
      'business_name': businessName,
      'database_sha256': databaseSha256.toLowerCase(),
      'total_invoices': totalInvoices,
      'total_customers': totalCustomers,
      'total_products': totalProducts,
      'backup_type': backupType,
    };
  }

  factory BackupManifest.fromMap(Map<String, dynamic> map) {
    return BackupManifest(
      formatVersion: map['format_version'] as int? ?? 1,
      appVersion: map['app_version'] as String? ?? '1.0.0',
      appBuildNumber: map['app_build_number'] as int? ?? 1,
      schemaVersion: map['schema_version'] as int? ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      businessId: map['business_id'] as String,
      businessName: map['business_name'] as String? ?? 'Unknown Business',
      databaseSha256: (map['database_sha256'] as String).toLowerCase(),
      totalInvoices: map['total_invoices'] as int? ?? 0,
      totalCustomers: map['total_customers'] as int? ?? 0,
      totalProducts: map['total_products'] as int? ?? 0,
      backupType: map['backup_type'] as String? ?? 'MANUAL',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory BackupManifest.fromJson(String source) =>
      BackupManifest.fromMap(jsonDecode(source) as Map<String, dynamic>);

  BackupManifest copyWith({
    int? formatVersion,
    String? appVersion,
    int? appBuildNumber,
    int? schemaVersion,
    DateTime? createdAt,
    String? businessId,
    String? businessName,
    String? databaseSha256,
    int? totalInvoices,
    int? totalCustomers,
    int? totalProducts,
    String? backupType,
  }) {
    return BackupManifest(
      formatVersion: formatVersion ?? this.formatVersion,
      appVersion: appVersion ?? this.appVersion,
      appBuildNumber: appBuildNumber ?? this.appBuildNumber,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      databaseSha256: databaseSha256 ?? this.databaseSha256,
      totalInvoices: totalInvoices ?? this.totalInvoices,
      totalCustomers: totalCustomers ?? this.totalCustomers,
      totalProducts: totalProducts ?? this.totalProducts,
      backupType: backupType ?? this.backupType,
    );
  }
}
