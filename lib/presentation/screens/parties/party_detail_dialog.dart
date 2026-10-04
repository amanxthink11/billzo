import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/purchase_providers.dart';
import 'package:billzo/presentation/screens/parties/party_form_dialog.dart';
import 'package:billzo/presentation/screens/payments/payment_form_dialog.dart';
import 'package:billzo/presentation/screens/payments/supplier_payment_dialog.dart';

/// Modal dialog displaying party overview, addresses, and actions.
class PartyDetailDialog extends ConsumerWidget {
  final Party party;

  const PartyDetailDialog({super.key, required this.party});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                    radius: 24,
                    child: Text(
                      party.name.isNotEmpty ? party.name[0].toUpperCase() : 'P',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillzoColors.primaryBlue),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                party.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildBadge(party.partyType.displayName, BillzoColors.primaryBlue),
                            if (!party.isActive) ...[
                              const SizedBox(width: 6),
                              _buildBadge('Inactive', BillzoColors.neutralText),
                            ],
                          ],
                        ),
                        if (party.companyName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            party.companyName!,
                            style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Balance & Credit Overview
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            'Current Balance',
                            '₹${(party.currentBalancePaise / 100).toStringAsFixed(2)}',
                            party.openingBalanceType == OpeningBalanceType.toReceive
                                ? BillzoColors.successGreen
                                : BillzoColors.dangerRed,
                            subtitle: party.openingBalanceType.displayName,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildInfoCard(
                            'Credit Limit',
                            party.creditLimitPaise > 0
                                ? '₹${(party.creditLimitPaise / 100).toStringAsFixed(0)}'
                                : 'No Limit',
                            BillzoColors.darkSlate,
                            subtitle: party.creditPeriodDays > 0 ? '${party.creditPeriodDays} days payment term' : 'No term set',
                          ),
                        ),
                      ],
                    ),
                    if (party.partyType == PartyType.supplier) ...[
                      const SizedBox(height: 16),
                      ref.watch(supplierAPSummaryProvider(party.id)).when(
                        data: (summary) => Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: BillzoColors.canvasLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BillzoColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.account_balance_wallet_outlined, size: 18, color: BillzoColors.primaryBlue),
                                  const SizedBox(width: 8),
                                  const Text('Accounts Payable Overview', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                  const Spacer(),
                                  Text('${summary.billCount} bills recorded', style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSubMetric('Total Purchased', Money(summary.totalPurchasesPaise).formatted),
                                  ),
                                  Expanded(
                                    child: _buildSubMetric('Total Paid', Money(summary.totalPaidPaise).formatted),
                                  ),
                                  Expanded(
                                    child: _buildSubMetric(
                                      'Outstanding Payable',
                                      Money(summary.outstandingPayablePaise).formatted,
                                      color: summary.outstandingPayablePaise > 0 ? BillzoColors.dangerRed : BillzoColors.successGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
                        error: (e, st) => const SizedBox.shrink(),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Contact Details
                    const Text('Contact Information', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _buildDetailRow(Icons.phone_outlined, 'Phone', party.phone != null ? '+91 ${party.phone}' : 'Not provided'),
                    if (party.alternatePhone != null)
                      _buildDetailRow(Icons.phone_android_outlined, 'Alternate Phone', '+91 ${party.alternatePhone}'),
                    _buildDetailRow(Icons.email_outlined, 'Email', party.email ?? 'Not provided'),
                    if (party.contactPerson != null)
                      _buildDetailRow(Icons.person_outline, 'Contact Person', party.contactPerson!),
                    const SizedBox(height: 20),

                    // Statutory & Tax Details
                    const Text('Tax & Statutory Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _buildDetailRow(Icons.assignment_outlined, 'GSTIN', party.gstin ?? 'Unregistered / None'),
                    _buildDetailRow(Icons.credit_card_outlined, 'PAN', party.pan ?? 'Not provided'),
                    const SizedBox(height: 20),

                    // Addresses
                    const Text('Addresses', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _buildAddressCard('Billing Address', party.billingAddressLine1, party.billingCity, party.billingStateName, party.billingPincode),
                    const SizedBox(height: 12),
                    if (party.shippingAddressLine1 != null)
                      _buildAddressCard('Shipping Address', party.shippingAddressLine1, party.shippingCity, party.shippingStateName, party.shippingPincode),
                    const SizedBox(height: 20),

                    // Notes
                    if (party.notes != null && party.notes!.isNotEmpty) ...[
                      const Text('Notes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: BillzoColors.canvasLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: BillzoColors.border),
                        ),
                        child: Text(party.notes!, style: const TextStyle(fontSize: 13, height: 1.4)),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final service = ref.read(partyServiceProvider);
                      if (party.isActive) {
                        await service.deactivateParty(party.id);
                      } else {
                        await service.reactivateParty(party.id);
                      }
                      ref.invalidate(partiesListProvider);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: Icon(party.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
                    label: Text(party.isActive ? 'Deactivate' : 'Reactivate'),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await showDialog(
                        context: context,
                        builder: (_) => PartyFormDialog(
                          businessId: party.businessId,
                          partyToEdit: party,
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit Details'),
                  ),
                  if (party.partyType == PartyType.customer) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BillzoColors.successGreen,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        final business = ref.read(activeBusinessProvider).value;
                        if (business != null) {
                          await PaymentFormDialog.show(
                            context,
                            business: business,
                            preselectedCustomer: party,
                          );
                          ref.invalidate(partiesListProvider);
                        }
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Receive Payment'),
                    ),
                  ],
                  if (party.partyType == PartyType.supplier) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BillzoColors.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        final business = ref.read(activeBusinessProvider).value;
                        if (business != null) {
                          await SupplierPaymentDialog.show(
                            context,
                            business: business,
                            preselectedSupplier: party,
                          );
                          ref.invalidate(partiesListProvider);
                          ref.invalidate(supplierAPSummaryProvider(party.id));
                        }
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Record Payment'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, Color color, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BillzoColors.canvasLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
          ],
        ],
      ),
    );
  }

  Widget _buildSubMetric(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color ?? BillzoColors.darkSlate,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: BillzoColors.neutralText),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(String title, String? line1, String? city, String? state, String? pincode) {
    final parts = [line1, city, state, pincode].where((p) => p != null && p.isNotEmpty).join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BillzoColors.canvasLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillzoColors.neutralText)),
          const SizedBox(height: 4),
          Text(
            parts.isNotEmpty ? parts : 'No address specified',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
