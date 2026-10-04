import 'package:flutter_test/flutter_test.dart';

import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/payment/payment_validator.dart';

void main() {
  group('Payment Domain Validation Tests', () {
    final now = DateTime(2026, 4, 15);

    Payment createTestPayment({
      String businessId = 'biz-1',
      String customerId = 'cust-1',
      int amountPaise = 100000, // ₹1,000.00
      List<PaymentAllocation> allocations = const [],
    }) {
      return Payment(
        id: 'pay-1',
        businessId: businessId,
        customerId: customerId,
        paymentNumber: 'PAY-2026-0001',
        paymentDate: now,
        paymentMethod: PaymentMethod.cash,
        amountPaise: amountPaise,
        status: PaymentStatus.posted,
        allocations: allocations,
        createdAt: now,
        updatedAt: now,
      );
    }

    Invoice createTestInvoice({
      String id = 'inv-1',
      String invoiceNumber = 'INV-2026-0001',
      InvoiceStatus status = InvoiceStatus.finalized,
      int totalAmountPaise = 100000,
      int balanceAmountPaise = 100000,
    }) {
      return Invoice(
        id: id,
        businessId: 'biz-1',
        customerId: 'cust-1',
        invoiceNumber: invoiceNumber,
        invoiceDate: now,
        dueDate: now,
        placeOfSupplyStateCode: '27',
        invoiceType: InvoiceType.taxInvoice,
        status: status,
        subtotalPaise: totalAmountPaise,
        taxableAmountPaise: totalAmountPaise,
        totalAmountPaise: totalAmountPaise,
        paidAmountPaise: totalAmountPaise - balanceAmountPaise,
        balanceAmountPaise: balanceAmountPaise,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('Valid payment without allocation passes validation', () {
      final payment = createTestPayment();
      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
      expect(result.firstError, isNull);
    });

    test('Rejects payment with zero amount', () {
      final payment = createTestPayment(amountPaise: 0);
      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('amount'), isTrue);
      expect(result.firstError, contains('greater than zero'));
    });

    test('Rejects payment with negative amount', () {
      final payment = createTestPayment(amountPaise: -5000);
      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('amount'), isTrue);
    });

    test('Rejects payment without customer ID', () {
      final payment = createTestPayment(customerId: '   ');
      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('customerId'), isTrue);
    });

    test('Rejects payment without business ID', () {
      final payment = createTestPayment(businessId: '');
      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('businessId'), isTrue);
    });

    test('Rejects payment when total allocated exceeds payment amount', () {
      final allocation = PaymentAllocation(
        id: 'alloc-1',
        paymentId: 'pay-1',
        documentId: 'inv-1',
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 150000, // ₹1,500 allocated
        createdAt: now,
        updatedAt: now,
      );
      final payment = createTestPayment(
        amountPaise: 100000, // ₹1,000 paid
        allocations: [allocation],
      );

      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('allocations'), isTrue);
      expect(result.firstError, contains('cannot exceed'));
    });

    test('Rejects payment containing zero or negative allocation amount', () {
      final allocation = PaymentAllocation(
        id: 'alloc-1',
        paymentId: 'pay-1',
        documentId: 'inv-1',
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 0,
        createdAt: now,
        updatedAt: now,
      );
      final payment = createTestPayment(allocations: [allocation]);

      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('allocation_inv-1'), isTrue);
    });

    test('Rejects duplicate allocation against same invoice in one payment', () {
      final alloc1 = PaymentAllocation(
        id: 'alloc-1',
        paymentId: 'pay-1',
        documentId: 'inv-1',
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 30000,
        createdAt: now,
        updatedAt: now,
      );
      final alloc2 = PaymentAllocation(
        id: 'alloc-2',
        paymentId: 'pay-1',
        documentId: 'inv-1', // Duplicate target invoice
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 40000,
        createdAt: now,
        updatedAt: now,
      );
      final payment = createTestPayment(
        amountPaise: 100000,
        allocations: [alloc1, alloc2],
      );

      final result = PaymentValidator.validate(payment);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('duplicate_inv-1'), isTrue);
    });

    test('Allocation against invoice: rejects draft invoice', () {
      final invoice = createTestInvoice(status: InvoiceStatus.draft);
      final allocation = PaymentAllocation(
        id: 'alloc-1',
        paymentId: 'pay-1',
        documentId: invoice.id,
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 50000,
        createdAt: now,
        updatedAt: now,
      );

      final result = PaymentValidator.validateAllocationAgainstInvoice(
        allocation: allocation,
        invoice: invoice,
      );

      expect(result.isValid, isFalse);
      expect(result.errors['status'], contains('draft invoice'));
    });

    test('Allocation against invoice: rejects cancelled invoice', () {
      final invoice = createTestInvoice(status: InvoiceStatus.cancelled);
      final allocation = PaymentAllocation(
        id: 'alloc-1',
        paymentId: 'pay-1',
        documentId: invoice.id,
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 50000,
        createdAt: now,
        updatedAt: now,
      );

      final result = PaymentValidator.validateAllocationAgainstInvoice(
        allocation: allocation,
        invoice: invoice,
      );

      expect(result.isValid, isFalse);
      expect(result.errors['status'], contains('cancelled invoice'));
    });

    test('Allocation against invoice: rejects over-allocation exceeding outstanding balance', () {
      final invoice = createTestInvoice(
        balanceAmountPaise: 40000, // ₹400.00 outstanding
      );
      final allocation = PaymentAllocation(
        id: 'alloc-1',
        paymentId: 'pay-1',
        documentId: invoice.id,
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 60000, // ₹600.00 attempted allocation
        createdAt: now,
        updatedAt: now,
      );

      final result = PaymentValidator.validateAllocationAgainstInvoice(
        allocation: allocation,
        invoice: invoice,
      );

      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('overAllocation'), isTrue);
      expect(result.firstError, contains('cannot exceed invoice outstanding balance'));
    });

    test('Allocation against invoice: valid exact or partial allocation succeeds', () {
      final invoice = createTestInvoice(balanceAmountPaise: 100000);
      final allocation = PaymentAllocation(
        id: 'alloc-1',
        paymentId: 'pay-1',
        documentId: invoice.id,
        documentType: 'TAX_INVOICE',
        allocatedAmountPaise: 100000, // Full ₹1,000
        createdAt: now,
        updatedAt: now,
      );

      final result = PaymentValidator.validateAllocationAgainstInvoice(
        allocation: allocation,
        invoice: invoice,
      );

      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
    });
  });
}
