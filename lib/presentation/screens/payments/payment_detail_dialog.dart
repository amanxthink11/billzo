import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';

/// Modal dialog displaying statutory customer payment receipt with cancellation capability.
class PaymentDetailDialog extends ConsumerStatefulWidget {
  final Payment payment;

  const PaymentDetailDialog({super.key, required this.payment});

  static Future<void> show(BuildContext context, {required Payment payment}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => PaymentDetailDialog(payment: payment),
    );
  }

  @override
  ConsumerState<PaymentDetailDialog> createState() => _PaymentDetailDialogState();
}

class _PaymentDetailDialogState extends ConsumerState<PaymentDetailDialog> {
  late Payment _payment;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _payment = widget.payment;
  }

  Future<void> _handleCancel() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: BillzoColors.dangerRed),
            SizedBox(width: 8),
            Text('Cancel Payment Receipt'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel payment ${_payment.paymentNumber} of ₹${_payment.amount.toIndianRupeeString()}?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Cancellation will safely reverse all invoice allocations, restore customer outstanding balances, and post reversing ledger entries.',
              style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation *',
                hintText: 'e.g. Bounced cheque, wrong customer, duplicate entry',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BillzoColors.dangerRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a cancellation reason.')),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Confirm Cancellation'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isCancelling = true);
      try {
        final service = ref.read(paymentServiceProvider);
        final cancelled = await service.cancelPayment(
          _payment.id,
          reason: reasonController.text.trim(),
        );

        ref.invalidate(paymentsListProvider(_payment.businessId));
        ref.invalidate(paymentsCountProvider(_payment.businessId));

        setState(() {
          _payment = cancelled;
          _isCancelling = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment ${_payment.paymentNumber} successfully cancelled.'),
              backgroundColor: BillzoColors.dangerRed,
            ),
          );
        }
      } catch (e) {
        setState(() => _isCancelling = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cancellation failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _payment.status.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.receipt_outlined, color: _payment.status.color, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _payment.paymentNumber,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BillzoColors.darkSlate),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _payment.status.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _payment.status.displayName,
                                  style: TextStyle(
                                    color: _payment.status.color,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Recorded on ${dateFormat.format(_payment.paymentDate)}',
                            style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const Divider(height: 24),

              if (_payment.isCancelled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: BillzoColors.dangerRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel, color: BillzoColors.dangerRed, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Payment Cancelled: ${_payment.cancellationReason ?? 'No reason provided'}',
                          style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

              // Content Body
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer Info & Account Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: BillzoColors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('RECEIVED FROM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: BillzoColors.neutralText)),
                                  const SizedBox(height: 4),
                                  Text(_payment.customerName ?? 'Customer', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate)),
                                  if (_payment.customerPhone != null)
                                    Text('Ph: ${_payment.customerPhone}', style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 48, color: BillzoColors.border),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('PAYMENT DETAILS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: BillzoColors.neutralText)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(_payment.paymentMethod.icon, size: 16, color: BillzoColors.neutralText),
                                      const SizedBox(width: 6),
                                      Text(_payment.paymentMethod.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  if (_payment.referenceNumber != null && _payment.referenceNumber!.isNotEmpty)
                                    Text('Ref: ${_payment.referenceNumber}', style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                  if (_payment.accountName != null)
                                    Text('Account: ${_payment.accountName}', style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Grand Amount Highlight
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: BillzoColors.primaryBlue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: BillzoColors.primaryBlue.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Amount Received', style: TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                const SizedBox(height: 2),
                                Text(
                                  '₹${_payment.amount.toIndianRupeeString()}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillzoColors.primaryBlue),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: BillzoColors.border),
                              ),
                              child: Text(
                                _payment.amountInWords,
                                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: BillzoColors.neutralText),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Invoices Allocated Table
                      const Text(
                        'Invoice Allocations',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                      ),
                      const SizedBox(height: 8),

                      if (_payment.allocations.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BillzoColors.border),
                          ),
                          child: const Center(
                            child: Text(
                              'Unallocated Payment (Held on Account as Customer Advance)',
                              style: TextStyle(color: BillzoColors.neutralText, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: BillzoColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(3),
                              1: FlexColumnWidth(3),
                              2: FlexColumnWidth(3),
                              3: FlexColumnWidth(3),
                            },
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                                children: [
                                  _th('Invoice #'),
                                  _th('Invoice Date'),
                                  _th('Total Amount', align: TextAlign.right),
                                  _th('Allocated Here', align: TextAlign.right),
                                ],
                              ),
                              for (final alloc in _payment.allocations)
                                TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(alloc.invoiceNumber ?? alloc.documentId, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(
                                        alloc.invoiceDate != null ? dateFormat.format(alloc.invoiceDate!) : '—',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(
                                        alloc.invoiceTotalPaise != null
                                            ? '₹${(alloc.invoiceTotalPaise! / 100.0).toStringAsFixed(2)}'
                                            : '—',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(
                                        '₹${alloc.allocatedAmount.toIndianRupeeString()}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.w700, color: BillzoColors.successGreen, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                      if (_payment.notes != null && _payment.notes!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_payment.notes!, style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText)),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_payment.isPosted)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BillzoColors.dangerRed,
                        side: const BorderSide(color: BillzoColors.dangerRed),
                      ),
                      icon: _isCancelling
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: BillzoColors.dangerRed))
                          : const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel Payment'),
                      onPressed: _isCancelling ? null : _handleCancel,
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: BillzoColors.neutralText),
      ),
    );
  }
}
