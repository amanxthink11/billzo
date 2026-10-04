import 'package:flutter/material.dart';
import 'package:billzo/core/theme/colors.dart';

/// Status lifecycle for a Purchase bill.
enum PurchaseStatus {
  draft,
  finalized,
  partiallyPaid,
  paid,
  cancelled;

  String get dbValue {
    switch (this) {
      case PurchaseStatus.draft:
        return 'DRAFT';
      case PurchaseStatus.finalized:
        return 'FINALIZED';
      case PurchaseStatus.partiallyPaid:
        return 'PARTIALLY_PAID';
      case PurchaseStatus.paid:
        return 'PAID';
      case PurchaseStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static PurchaseStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'DRAFT':
        return PurchaseStatus.draft;
      case 'FINALIZED':
      case 'RECEIVED':
        return PurchaseStatus.finalized;
      case 'PARTIALLY_PAID':
      case 'PARTIALLY_RECEIVED':
        return PurchaseStatus.partiallyPaid;
      case 'PAID':
        return PurchaseStatus.paid;
      case 'CANCELLED':
        return PurchaseStatus.cancelled;
      default:
        return PurchaseStatus.draft;
    }
  }

  String get displayName {
    switch (this) {
      case PurchaseStatus.draft:
        return 'Draft';
      case PurchaseStatus.finalized:
        return 'Finalized';
      case PurchaseStatus.partiallyPaid:
        return 'Partially Paid';
      case PurchaseStatus.paid:
        return 'Paid';
      case PurchaseStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case PurchaseStatus.draft:
        return BillzoColors.neutralText;
      case PurchaseStatus.finalized:
        return BillzoColors.primaryBlue;
      case PurchaseStatus.partiallyPaid:
        return BillzoColors.accentOrange;
      case PurchaseStatus.paid:
        return BillzoColors.successGreen;
      case PurchaseStatus.cancelled:
        return BillzoColors.dangerRed;
    }
  }

  IconData get icon {
    switch (this) {
      case PurchaseStatus.draft:
        return Icons.edit_note;
      case PurchaseStatus.finalized:
        return Icons.check_circle_outline;
      case PurchaseStatus.partiallyPaid:
        return Icons.timelapse;
      case PurchaseStatus.paid:
        return Icons.task_alt;
      case PurchaseStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }
}
