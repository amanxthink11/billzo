import 'package:flutter/foundation.dart';

/// Unit of measurement for products and services.
@immutable
class UnitOfMeasurement {
  final String id;
  final String businessId;
  final String name;
  final String shortName;
  final bool isDecimalAllowed;
  final int decimalPlaces;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UnitOfMeasurement({
    required this.id,
    required this.businessId,
    required this.name,
    required this.shortName,
    this.isDecimalAllowed = false,
    this.decimalPlaces = 0,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Compatibility alias for [shortName].
  String get code => shortName;

  /// Compatibility alias for [isDecimalAllowed].
  bool get allowDecimal => isDecimalAllowed;

  UnitOfMeasurement copyWith({
    String? id,
    String? businessId,
    String? name,
    String? shortName,
    bool? isDecimalAllowed,
    int? decimalPlaces,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UnitOfMeasurement(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      isDecimalAllowed: isDecimalAllowed ?? this.isDecimalAllowed,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'code': shortName,
      'allow_decimal': isDecimalAllowed ? 1 : 0,
      'is_active': 1,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_version': 1,
      'sync_status': 'synced',
    };
  }

  factory UnitOfMeasurement.fromMap(Map<String, dynamic> map) {
    return UnitOfMeasurement(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      shortName: (map['code'] ?? map['short_name'] ?? '') as String,
      isDecimalAllowed: (map['allow_decimal'] as int? ?? (map['is_decimal_allowed'] as int? ?? 0)) == 1,
      decimalPlaces: (map['allow_decimal'] as int? ?? 0) == 1 ? 3 : 0,
      isDefault: false,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
