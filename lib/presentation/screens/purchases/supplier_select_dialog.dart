import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/screens/parties/party_form_dialog.dart';

/// Fast-search supplier selector modal dialog for the Purchase Builder.
class SupplierSelectDialog extends ConsumerStatefulWidget {
  final String businessId;

  const SupplierSelectDialog({
    super.key,
    required this.businessId,
  });

  @override
  ConsumerState<SupplierSelectDialog> createState() => _SupplierSelectDialogState();
}

class _SupplierSelectDialogState extends ConsumerState<SupplierSelectDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Party> _suppliers = [];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    final partyRepo = ref.read(partyRepositoryProvider);
    try {
      final list = await partyRepo.getParties(
        businessId: widget.businessId,
        typeFilter: PartyType.supplier,
        searchQuery: _query.trim().isEmpty ? null : _query.trim(),
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _suppliers = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String val) {
    setState(() => _query = val);
    _loadSuppliers();
  }

  void _openAddSupplierDialog() async {
    final newSupplier = await showDialog<Party>(
      context: context,
      builder: (_) => PartyFormDialog(
        businessId: widget.businessId,
      ),
    );

    if (newSupplier != null && mounted) {
      Navigator.of(context).pop(newSupplier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 580),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_outlined, color: BillzoColors.primaryBlue, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Select Supplier',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BillzoColors.darkSlate,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: BillzoColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('+ New Supplier', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: _openAddSupplierDialog,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by supplier name, phone, or GSTIN...',
                  prefixIcon: const Icon(Icons.search, size: 18, color: BillzoColors.neutralText),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: BillzoColors.border),
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),

            // List of Suppliers
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _suppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_off_outlined, size: 36, color: BillzoColors.neutralText),
                              const SizedBox(height: 8),
                              Text(
                                _query.isEmpty ? 'No suppliers registered yet.' : 'No supplier matches "$_query"',
                                style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: BillzoColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Supplier'),
                                onPressed: _openAddSupplierDialog,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _suppliers.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, color: BillzoColors.border),
                          itemBuilder: (ctx, idx) {
                            final supplier = _suppliers[idx];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              title: Row(
                                children: [
                                  Text(
                                    supplier.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  if (supplier.companyName != null && supplier.companyName!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '(${supplier.companyName})',
                                      style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  if (supplier.phone != null && supplier.phone!.isNotEmpty) ...[
                                    Icon(Icons.phone, size: 12, color: BillzoColors.neutralText),
                                    const SizedBox(width: 4),
                                    Text(supplier.phone!, style: const TextStyle(fontSize: 11)),
                                    const SizedBox(width: 12),
                                  ],
                                  if (supplier.gstin != null && supplier.gstin!.isNotEmpty) ...[
                                    Text('GSTIN: ${supplier.gstin}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    supplier.currentBalancePaise > 0
                                        ? 'Payable: ${Money.formatPaise(supplier.currentBalancePaise)}'
                                        : 'Settled',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: supplier.currentBalancePaise > 0 ? BillzoColors.dangerRed : BillzoColors.successGreen,
                                    ),
                                  ),
                                  if (supplier.billingStateName != null)
                                    Text(
                                      supplier.billingStateName!,
                                      style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                    ),
                                ],
                              ),
                              onTap: () => Navigator.of(context).pop(supplier),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
