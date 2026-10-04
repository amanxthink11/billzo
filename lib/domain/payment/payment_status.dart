import 'package:flutter/material.dart';
import 'package:billzo/core/theme/colors.dart';

/// Lifecycle statuses for customer payments.
enum PaymentStatus {
  draft,
  posted,
  cancelled;

  String get dbValue {
    switch (this) {
      case PaymentStatus.draft:
        return 'DRAFT';
      case PaymentStatus.posted:
        return 'POSTED';
      case PaymentStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static PaymentStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'DRAFT':
        return PaymentStatus.draft;
      case 'POSTED':
        return PaymentStatus.posted;
      case 'CANCELLED':
        return PaymentStatus.cancelled;
      default:
        return PaymentStatus.posted;
    }
  }

  String get displayName {
    switch (this) {
      case PaymentStatus.draft:
        return 'Draft';
      case PaymentStatus.posted:
        return 'Posted';
      case PaymentStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case PaymentStatus.draft:
        return const Color(0xFF64748B); // Slate grey
      case PaymentStatus.posted:
        return BillzoColors.successGreen;
      case PaymentStatus.cancelled:
        return BillzoColors.dangerRed;
    }
  }

  Color get backgroundColor => color.withValues(alpha: 0.1);
}
