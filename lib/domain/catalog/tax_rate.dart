import 'package:flutter/foundation.dart';

/// Statutory GST tax rate bracket.
@immutable
class TaxRate {
  final String id;
  final String businessId;
  final String name;
  final int rateBasisPoints;
  final int cgstBasisPoints;
  final int sgstBasisPoints;
  final int igstBasisPoints;
  final int cessBasisPoints;
  final bool isDefault;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaxRate({
    required this.id,
    required this.businessId,
    required this.name,
    required this.rateBasisPoints,
    required this.cgstBasisPoints,
    required this.sgstBasisPoints,
    required this.igstBasisPoints,
    this.cessBasisPoints = 0,
    this.isDefault = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  double get ratePercentage => rateBasisPoints / 100.0;
  String get displayPercentage =>
      '${(rateBasisPoints / 100).toStringAsFixed(rateBasisPoints % 100 == 0 ? 0 : 2)}%';

  TaxRate copyWith({
    String? id,
    String? businessId,
    String? name,
    int? rateBasisPoints,
    int? cgstBasisPoints,
    int? sgstBasisPoints,
    int? igstBasisPoints,
    int? cessBasisPoints,
    bool? isDefault,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaxRate(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      rateBasisPoints: rateBasisPoints ?? this.rateBasisPoints,
      cgstBasisPoints: cgstBasisPoints ?? this.cgstBasisPoints,
      sgstBasisPoints: sgstBasisPoints ?? this.sgstBasisPoints,
      igstBasisPoints: igstBasisPoints ?? this.igstBasisPoints,
      cessBasisPoints: cessBasisPoints ?? this.cessBasisPoints,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'rate_basis_points': rateBasisPoints,
      'cgst_basis_points': cgstBasisPoints,
      'sgst_basis_points': sgstBasisPoints,
      'igst_basis_points': igstBasisPoints,
      'cess_basis_points': cessBasisPoints,
      'is_default': isDefault ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory TaxRate.fromMap(Map<String, dynamic> map) {
    return TaxRate(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      rateBasisPoints: map['rate_basis_points'] as int,
      cgstBasisPoints: map['cgst_basis_points'] as int,
      sgstBasisPoints: map['sgst_basis_points'] as int,
      igstBasisPoints: map['igst_basis_points'] as int,
      cessBasisPoints: map['cess_basis_points'] as int? ?? 0,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
