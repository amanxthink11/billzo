import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';

void main() {
  const uuid = Uuid();

  group('Invoice Payment Status Regression Tests', () {
    Invoice createTestInvoice({
      required int totalPaise,
      required int paidPaise,
      InvoiceStatus status = InvoiceStatus.finalized,
    }) {
      final balancePaise = (totalPaise - paidPaise).clamp(0, totalPaise);
      return Invoice(
        id: uuid.v4(),
        businessId: 'biz-test',
        invoiceNumber: 'INV-2026-9999',
        customerId: 'cust-test',
        customerName: 'Aman Singh',
        invoiceDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 15),
        placeOfSupplyStateCode: '27',
        status: status,
        subtotalPaise: totalPaise,
        taxableAmountPaise: totalPaise,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: totalPaise,
        paidAmountPaise: paidPaise,
        balanceAmountPaise: balancePaise,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
    }

    test('Zero paid amount derives DUE status', () {
      final inv = createTestInvoice(totalPaise: 99900, paidPaise: 0);

      expect(inv.paidAmountPaise, equals(0));
      expect(inv.balanceAmountPaise, equals(99900));
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.due));
      expect(inv.isDue, isTrue);
      expect(inv.isPartiallyPaid, isFalse);
      expect(inv.isPaid, isFalse);
      expect(inv.paymentStatus.displayName, equals('Due'));
      expect(inv.paymentStatus.code, equals('DUE'));
    });

    test('Partial payment derives PARTIALLY PAID status with correct paid and due amounts', () {
      final inv = createTestInvoice(totalPaise: 99900, paidPaise: 50000);

      expect(inv.paidAmount, equals(Money.fromPaise(50000)));
      expect(inv.balanceAmount, equals(Money.fromPaise(49900)));
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.partiallyPaid));
      expect(inv.isDue, isFalse);
      expect(inv.isPartiallyPaid, isTrue);
      expect(inv.isPaid, isFalse);
      expect(inv.paymentStatus.displayName, equals('Partially Paid'));
      expect(inv.paymentStatus.code, equals('PARTIALLY PAID'));
    });

    test('Full payment derives PAID status with 0 balance', () {
      final inv = createTestInvoice(totalPaise: 99900, paidPaise: 99900);

      expect(inv.paidAmountPaise, equals(99900));
      expect(inv.balanceAmountPaise, equals(0));
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.paid));
      expect(inv.isDue, isFalse);
      expect(inv.isPartiallyPaid, isFalse);
      expect(inv.isPaid, isTrue);
      expect(inv.paymentStatus.displayName, equals('Paid'));
      expect(inv.paymentStatus.code, equals('PAID'));
    });

    test('Payment status updates correctly on subsequent payment allocation and reversal', () {
      // Step 1: Initial state = Due
      var inv = createTestInvoice(totalPaise: 100000, paidPaise: 0);
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.due));

      // Step 2: Customer pays ₹400 -> Partially Paid
      inv = inv.copyWith(paidAmountPaise: 40000, balanceAmountPaise: 60000);
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.partiallyPaid));

      // Step 3: Customer clears remainder ₹600 -> Paid
      inv = inv.copyWith(paidAmountPaise: 100000, balanceAmountPaise: 0);
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.paid));

      // Step 4: Reversal of second payment (e.g. cheque bounce / refund) -> Back to Partially Paid
      inv = inv.copyWith(paidAmountPaise: 40000, balanceAmountPaise: 60000);
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.partiallyPaid));

      // Step 5: Reversal of first payment -> Back to Due
      inv = inv.copyWith(paidAmountPaise: 0, balanceAmountPaise: 100000);
      expect(inv.paymentStatus, equals(InvoicePaymentStatus.due));
    });

    test('Lifecycle status is completely decoupled from payment status', () {
      // Draft invoice
      final draft = createTestInvoice(totalPaise: 50000, paidPaise: 0, status: InvoiceStatus.draft);
      expect(draft.lifecycleStatus, equals(InvoiceLifecycleStatus.draft));
      expect(draft.paymentStatus, equals(InvoicePaymentStatus.due));

      // Finalized invoice
      final finalized = createTestInvoice(totalPaise: 50000, paidPaise: 50000, status: InvoiceStatus.finalized);
      expect(finalized.lifecycleStatus, equals(InvoiceLifecycleStatus.finalized));
      expect(finalized.paymentStatus, equals(InvoicePaymentStatus.paid));

      // Cancelled invoice
      final cancelled = createTestInvoice(totalPaise: 50000, paidPaise: 0, status: InvoiceStatus.cancelled);
      expect(cancelled.lifecycleStatus, equals(InvoiceLifecycleStatus.cancelled));
      expect(cancelled.paymentStatus, equals(InvoicePaymentStatus.due));
    });
  });
}
