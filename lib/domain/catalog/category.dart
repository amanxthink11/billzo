import 'package:flutter/foundation.dart';

/// Product or Service classification category.
@immutable
class Category {
  final String id;
  final String businessId;
  final String? parentId;
  final String name;
  final String? description;
  final String? colorHex;
  final String? iconName;
  final int sortOrder;
  final bool isActive;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Category({
    required this.id,
    required this.businessId,
    this.parentId,
    required this.name,
    this.description,
    this.colorHex,
    this.iconName,
    this.sortOrder = 0,
    this.isActive = true,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Category copyWith({
    String? id,
    String? businessId,
    String? parentId,
    String? name,
    String? description,
    String? colorHex,
    String? iconName,
    int? sortOrder,
    bool? isActive,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      description: description ?? this.description,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'parent_category_id': parentId,
      'color_hex': colorHex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': isDeleted ? updatedAt.toIso8601String() : null,
      'sync_version': 1,
      'sync_status': 'synced',
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      parentId: (map['parent_category_id'] ?? map['parent_id']) as String?,
      name: map['name'] as String,
      description: map['description'] as String?,
      colorHex: map['color_hex'] as String?,
      iconName: map['icon_name'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isDeleted: map['deleted_at'] != null || (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
