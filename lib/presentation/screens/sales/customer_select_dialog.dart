import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/screens/parties/party_form_dialog.dart';

/// Fast-search customer selector modal dialog for the Invoice Builder.
class CustomerSelectDialog extends ConsumerStatefulWidget {
  final String businessId;

  const CustomerSelectDialog({
    super.key,
    required this.businessId,
  });

  @override
  ConsumerState<CustomerSelectDialog> createState() => _CustomerSelectDialogState();
}

class _CustomerSelectDialogState extends ConsumerState<CustomerSelectDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Party> _customers = [];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    final partyRepo = ref.read(partyRepositoryProvider);
    try {
      final list = await partyRepo.getParties(
        businessId: widget.businessId,
        typeFilter: PartyType.customer,
        searchQuery: _query.trim().isEmpty ? null : _query.trim(),
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _customers = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Customer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar + Add Customer Button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search by customer name, phone, or GSTIN...',
                        prefixIcon: const Icon(Icons.search, size: 20, color: BillzoColors.neutralText),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _query = '';
                                  _loadCustomers();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: BillzoColors.border),
                        ),
                      ),
                      onChanged: (val) {
                        _query = val;
                        _loadCustomers();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Add Customer'),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final newParty = await showDialog<Party>(
                        context: context,
                        builder: (_) => PartyFormDialog(
                          businessId: widget.businessId,
                          initialPartyType: PartyType.customer,
                        ),
                      );
                      if (newParty != null) {
                        nav.pop(newParty);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Customer List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _customers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_search, size: 48, color: BillzoColors.neutralText),
                                const SizedBox(height: 8),
                                Text(
                                  _query.isEmpty ? 'No customers found' : 'No matching customers for "$_query"',
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: BillzoColors.neutralText),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Click "+ Add Customer" above to create one.',
                                  style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _customers.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, color: BillzoColors.border),
                            itemBuilder: (context, index) {
                              final party = _customers[index];
                              final balPaise = party.currentBalancePaise;
                              final balFormatted = Money.fromPaise(balPaise).toIndianRupeeString();

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFEFF6FF),
                                  child: Text(
                                    party.name.isNotEmpty ? party.name[0].toUpperCase() : 'C',
                                    style: const TextStyle(
                                      color: BillzoColors.primaryBlue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        party.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      balPaise > 0 ? 'Due: $balFormatted' : 'Bal: $balFormatted',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: balPaise > 0 ? BillzoColors.dangerRed : BillzoColors.neutralText,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        if (party.phone != null && party.phone!.isNotEmpty) ...[
                                          const Icon(Icons.phone, size: 12, color: BillzoColors.neutralText),
                                          const SizedBox(width: 4),
                                          Text(party.phone!, style: const TextStyle(fontSize: 12)),
                                          const SizedBox(width: 12),
                                        ],
                                        if (party.gstin != null && party.gstin!.isNotEmpty) ...[
                                          const Icon(Icons.badge_outlined, size: 12, color: BillzoColors.neutralText),
                                          const SizedBox(width: 4),
                                          Text('GST: ${party.gstin!}', style: const TextStyle(fontSize: 12)),
                                          const SizedBox(width: 12),
                                        ],
                                        if (party.billingStateCode != null) ...[
                                          const Icon(Icons.location_on_outlined, size: 12, color: BillzoColors.neutralText),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${party.billingStateName ?? ''} (${party.billingStateCode})',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                hoverColor: const Color(0xFFEFF6FF),
                                onTap: () => Navigator.of(context).pop(party),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
