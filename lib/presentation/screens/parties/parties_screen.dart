import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/screens/parties/party_detail_dialog.dart';
import 'package:billzo/presentation/screens/parties/party_form_dialog.dart';

/// Desktop-first view for managing Customers, Suppliers, and Both.
class PartiesScreen extends ConsumerStatefulWidget {
  final Business business;
  final PartyType? initialTypeFilter;

  const PartiesScreen({
    super.key,
    required this.business,
    this.initialTypeFilter,
  });

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialTypeFilter != null) {
        ref.read(partyTypeFilterProvider.notifier).setFilter(widget.initialTypeFilter);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeFilter = ref.watch(partyTypeFilterProvider);
    final partiesAsync = ref.watch(partiesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Action Header
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Search Input
                  SizedBox(
                    width: 280,
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, phone, GSTIN...',
                        prefixIcon: const Icon(Icons.search, size: 18, color: BillzoColors.neutralText),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(partySearchQueryProvider.notifier).setQuery('');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: BillzoColors.border),
                        ),
                      ),
                      onChanged: (val) {
                        ref.read(partySearchQueryProvider.notifier).setQuery(val);
                      },
                    ),
                  ),

                  // Filter Chips / Segments
                  SegmentedButton<PartyType?>(
                    segments: const [
                      ButtonSegment(value: null, label: Text('All')),
                      ButtonSegment(value: PartyType.customer, label: Text('Customers')),
                      ButtonSegment(value: PartyType.supplier, label: Text('Suppliers')),
                    ],
                    selected: {activeFilter},
                    onSelectionChanged: (set) {
                      ref.read(partyTypeFilterProvider.notifier).setFilter(set.first);
                    },
                  ),
                ],
              ),

              // Quick Actions
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openPartyForm(PartyType.supplier),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Supplier'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openPartyForm(PartyType.customer),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Customer'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Parties Table Canvas
          Expanded(
            child: Card(
              child: partiesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Text('Error loading parties: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
                ),
                data: (parties) {
                  if (parties.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowHeight: 48,
                          dataRowMinHeight: 52,
                          dataRowMaxHeight: 58,
                          headingRowColor: WidgetStateProperty.all(BillzoColors.canvasLight),
                          columns: const [
                            DataColumn(label: Text('PARTY NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('TYPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('PHONE / EMAIL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('GSTIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('STATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('BALANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                          ],
                          rows: parties.map((party) {
                            return DataRow(
                              cells: [
                                // Name & Company
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        party.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      if (party.companyName != null)
                                        Text(
                                          party.companyName!,
                                          style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                        ),
                                    ],
                                  ),
                                  onTap: () => _openPartyDetail(party),
                                ),

                                // Type
                                DataCell(
                                  _buildTypeBadge(party.partyType),
                                  onTap: () => _openPartyDetail(party),
                                ),

                                // Phone / Email
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        party.phone != null ? '+91 ${party.phone}' : '—',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      if (party.email != null)
                                        Text(
                                          party.email!,
                                          style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                        ),
                                    ],
                                  ),
                                  onTap: () => _openPartyDetail(party),
                                ),

                                // GSTIN
                                DataCell(
                                  Text(
                                    party.gstin ?? '—',
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                  ),
                                  onTap: () => _openPartyDetail(party),
                                ),

                                // State
                                DataCell(
                                  Text(
                                    party.billingStateName != null
                                        ? '${party.billingStateCode} - ${party.billingStateName}'
                                        : '—',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () => _openPartyDetail(party),
                                ),

                                // Balance
                                DataCell(
                                  Text(
                                    '₹${(party.currentBalancePaise / 100).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: party.currentBalancePaise == 0
                                          ? BillzoColors.darkSlate
                                          : party.openingBalanceType == OpeningBalanceType.toReceive
                                              ? BillzoColors.successGreen
                                              : BillzoColors.dangerRed,
                                    ),
                                  ),
                                  onTap: () => _openPartyDetail(party),
                                ),

                                // Actions
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.visibility_outlined, size: 18),
                                        tooltip: 'View Details',
                                        onPressed: () => _openPartyDetail(party),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        tooltip: 'Edit Party',
                                        onPressed: () => _openPartyForm(party.partyType, partyToEdit: party),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: BillzoColors.dangerRed),
                                        tooltip: 'Delete Party',
                                        onPressed: () => _confirmDelete(party),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline, size: 36, color: BillzoColors.primaryBlue),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Parties Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your customers and suppliers to track balances and prepare for invoicing.',
              style: TextStyle(color: BillzoColors.neutralText, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openPartyForm(PartyType.supplier),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Supplier'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _openPartyForm(PartyType.customer),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Customer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(PartyType type) {
    Color color;
    switch (type) {
      case PartyType.customer:
        color = BillzoColors.primaryBlue;
        break;
      case PartyType.supplier:
        color = BillzoColors.accentOrange;
        break;
      case PartyType.both:
        color = Colors.purple;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.displayName,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  void _openPartyForm(PartyType defaultType, {Party? partyToEdit}) {
    showDialog(
      context: context,
      builder: (_) => PartyFormDialog(
        businessId: widget.business.id,
        initialPartyType: defaultType,
        partyToEdit: partyToEdit,
      ),
    );
  }

  void _openPartyDetail(Party party) {
    showDialog(
      context: context,
      builder: (_) => PartyDetailDialog(party: party),
    );
  }

  Future<void> _confirmDelete(Party party) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Party?'),
        content: Text('Are you sure you want to remove "${party.name}"? This party will be soft-deleted and preserved for historical compliance.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = ref.read(partyServiceProvider);
      await service.deleteParty(party.id);
      ref.invalidate(partiesListProvider);
    }
  }
}
