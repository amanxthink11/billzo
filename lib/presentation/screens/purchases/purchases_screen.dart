import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/purchase_providers.dart';
import 'package:billzo/presentation/screens/payments/supplier_payment_dialog.dart';
import 'package:billzo/presentation/screens/purchases/purchase_builder_screen.dart';
import 'package:billzo/presentation/screens/purchases/purchase_detail_dialog.dart';
import 'package:billzo/presentation/screens/purchases/purchase_return_dialog.dart';

/// Screen listing purchase bills with real-time search, status filtering,
/// supplier filtering, date range filtering, KPI summary cards, and quick actions.
class PurchasesScreen extends ConsumerStatefulWidget {
  final Business business;

  const PurchasesScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openNewPurchase() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseBuilderScreen(business: widget.business),
      ),
    );
  }

  void _openPurchaseDetail(Purchase purchase) {
    PurchaseDetailDialog.show(
      context,
      business: widget.business,
      purchaseId: purchase.id,
      onEditDraft: purchase.status == PurchaseStatus.draft
          ? () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PurchaseBuilderScreen(
                    business: widget.business,
                    purchaseToEdit: purchase,
                  ),
                ),
              );
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchasesListProvider);
    final currentStatus = ref.watch(purchaseStatusFilterProvider);
    final currentSupplierId = ref.watch(purchaseSupplierFilterProvider);
    final currentDateRange = ref.watch(purchaseDateRangeProvider);
    final partiesAsync = ref.watch(partiesListProvider);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Section: Module Title + Primary CTA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Purchases & Accounts Payable',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: BillzoColors.darkSlate,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Record supplier bills, track Input Tax Credit (ITC), and manage payables.',
                    style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BillzoColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'New Purchase Bill',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _openNewPurchase,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Summary KPI Metric Cards
          purchasesAsync.maybeWhen(
            data: (list) => _buildMetricCards(list),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // 3. Filter & Search Toolbar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BillzoColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: BillzoColors.border),
            ),
            child: Row(
              children: [
                // Search Input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search purchase #, supplier, or invoice #...',
                        prefixIcon: const Icon(Icons.search, size: 18, color: BillzoColors.neutralText),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(purchaseSearchQueryProvider.notifier).state = '';
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: BillzoColors.border),
                        ),
                      ),
                      onChanged: (val) {
                        ref.read(purchaseSearchQueryProvider.notifier).state = val;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Supplier Filter Dropdown
                partiesAsync.maybeWhen(
                  data: (parties) {
                    final suppliers = parties.where((p) => p.partyType == PartyType.supplier).toList();
                    return Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: BillzoColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: currentSupplierId,
                          hint: const Text('All Suppliers', style: TextStyle(fontSize: 12)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Suppliers', style: TextStyle(fontSize: 12)),
                            ),
                            ...suppliers.map((s) {
                              return DropdownMenuItem<String?>(
                                value: s.id,
                                child: Text(s.name, style: const TextStyle(fontSize: 12)),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            ref.read(purchaseSupplierFilterProvider.notifier).state = val;
                          },
                        ),
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(width: 12),

                // Status Filter Dropdown
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: BillzoColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PurchaseStatus?>(
                      value: currentStatus,
                      hint: const Text('Status: All', style: TextStyle(fontSize: 12)),
                      items: [
                        const DropdownMenuItem<PurchaseStatus?>(
                          value: null,
                          child: Text('All Statuses', style: TextStyle(fontSize: 12)),
                        ),
                        ...PurchaseStatus.values.map((s) {
                          return DropdownMenuItem<PurchaseStatus?>(
                            value: s,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(s.displayName, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        ref.read(purchaseStatusFilterProvider.notifier).state = val;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Date Range Filter Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.date_range, size: 16, color: BillzoColors.neutralText),
                  label: Text(
                    currentDateRange != null
                        ? '${DateFormat('dd/MM').format(currentDateRange.start)} - ${DateFormat('dd/MM').format(currentDateRange.end)}'
                        : 'Date Range',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      initialDateRange: currentDateRange,
                    );
                    ref.read(purchaseDateRangeProvider.notifier).state = picked;
                  },
                ),
                if (currentDateRange != null) ...[
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      ref.read(purchaseDateRangeProvider.notifier).state = null;
                    },
                  ),
                ],

                const Spacer(),

                // Refresh Button
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh Purchases',
                  onPressed: () {
                    ref.invalidate(purchasesListProvider);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Purchases DataTable
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: BillzoColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BillzoColors.border),
              ),
              child: purchasesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40, color: BillzoColors.dangerRed),
                      const SizedBox(height: 12),
                      Text('Error loading purchases: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
                    ],
                  ),
                ),
                data: (purchases) {
                  if (purchases.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_cart_outlined, size: 48, color: BillzoColors.neutralText),
                          const SizedBox(height: 12),
                          const Text(
                            'No purchase bills found',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Record purchase bills from suppliers to track stock, ITC, and payables.',
                            style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BillzoColors.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Create First Purchase Bill'),
                            onPressed: _openNewPurchase,
                          ),
                        ],
                      ),
                    );
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(160), // Purchase #
                          1: FlexColumnWidth(2),    // Supplier
                          2: FixedColumnWidth(130), // Supplier Inv #
                          3: FixedColumnWidth(100), // Bill Date
                          4: FixedColumnWidth(120), // Total (₹)
                          5: FixedColumnWidth(100), // Paid (₹)
                          6: FixedColumnWidth(110), // Balance (₹)
                          7: FixedColumnWidth(110), // Status
                          8: FixedColumnWidth(60),  // Actions
                        },
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                            children: [
                              _th('Purchase #'),
                              _th('Supplier'),
                              _th('Supplier Inv #'),
                              _th('Bill Date'),
                              _th('Total (₹)', align: TextAlign.right),
                              _th('Paid (₹)', align: TextAlign.right),
                              _th('Balance (₹)', align: TextAlign.right),
                              _th('Status', align: TextAlign.center),
                              _th('', align: TextAlign.center),
                            ],
                          ),
                          for (final purchase in purchases)
                            _buildPurchaseTableRow(purchase, dateFormat),
                        ],
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

  Widget _th(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: BillzoColors.neutralText),
      ),
    );
  }

  TableRow _buildPurchaseTableRow(Purchase purchase, DateFormat dateFormat) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: BillzoColors.border.withValues(alpha: 0.5))),
      ),
      children: [
        // Purchase #
        InkWell(
          onTap: () => _openPurchaseDetail(purchase),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, size: 16, color: BillzoColors.primaryBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    purchase.purchaseNumber,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BillzoColors.primaryBlue),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Supplier
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            purchase.supplierName ?? 'Supplier',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Supplier Invoice #
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            purchase.supplierInvoiceNumber ?? '-',
            style: const TextStyle(fontSize: 12, color: BillzoColors.darkSlate),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Bill Date
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            dateFormat.format(purchase.purchaseDate),
            style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
          ),
        ),
        // Total (₹)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            Money.formatPaise(purchase.totalAmountPaise),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
          ),
        ),
        // Paid (₹)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            Money.formatPaise(purchase.paidAmountPaise),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillzoColors.successGreen),
          ),
        ),
        // Balance (₹)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            Money.formatPaise(purchase.balanceAmountPaise),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: purchase.balanceAmountPaise > 0 ? BillzoColors.dangerRed : BillzoColors.neutralText,
            ),
          ),
        ),
        // Status
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Center(child: _buildStatusBadge(purchase.status)),
        ),
        // Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            tooltip: 'Actions',
            onSelected: (action) {
              switch (action) {
                case 'view':
                  _openPurchaseDetail(purchase);
                  break;
                case 'payment':
                  SupplierPaymentDialog.show(
                    context,
                    business: widget.business,
                    preselectedPurchase: purchase,
                  );
                  break;
                case 'return':
                  PurchaseReturnDialog.show(
                    context,
                    originalPurchase: purchase,
                  );
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('View Bill', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              if ((purchase.status == PurchaseStatus.finalized ||
                      purchase.status == PurchaseStatus.partiallyPaid) &&
                  purchase.balanceAmountPaise > 0)
                const PopupMenuItem(
                  value: 'payment',
                  child: Row(
                    children: [
                      Icon(Icons.payment, size: 16, color: BillzoColors.successGreen),
                      SizedBox(width: 8),
                      Text('Record Payment', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              if (purchase.status == PurchaseStatus.finalized ||
                  purchase.status == PurchaseStatus.partiallyPaid ||
                  purchase.status == PurchaseStatus.paid)
                const PopupMenuItem(
                  value: 'return',
                  child: Row(
                    children: [
                      Icon(Icons.assignment_return_outlined, size: 16, color: BillzoColors.accentOrange),
                      SizedBox(width: 8),
                      Text('Debit Note / Return', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCards(List<Purchase> purchases) {
    int totalPurchased = 0;
    int todayPurchased = 0;
    int outstandingPayable = 0;
    int totalEligibleItc = 0;

    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    for (final p in purchases) {
      if (p.status != PurchaseStatus.cancelled) {
        totalPurchased += p.totalAmountPaise;
        outstandingPayable += p.balanceAmountPaise;
        totalEligibleItc += p.eligibleItcPaise;

        final pDateStr = DateFormat('yyyy-MM-dd').format(p.purchaseDate);
        if (pDateStr == todayStr) {
          todayPurchased += p.totalAmountPaise;
        }
      }
    }

    return Row(
      children: [
        Expanded(
          child: _metricCard(
            'Total Purchases',
            Money.formatPaise(totalPurchased),
            Icons.shopping_bag_outlined,
            BillzoColors.primaryBlue,
            '${purchases.where((p) => p.status != PurchaseStatus.cancelled).length} active bills',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'Today\'s Purchases',
            Money.formatPaise(todayPurchased),
            Icons.today_outlined,
            BillzoColors.accentOrange,
            'Purchased today',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'Outstanding Payable',
            Money.formatPaise(outstandingPayable),
            Icons.outbox_outlined,
            BillzoColors.dangerRed,
            'Supplier debt',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'Input Tax Credit (ITC)',
            Money.formatPaise(totalEligibleItc),
            Icons.verified_outlined,
            BillzoColors.successGreen,
            'Eligible GST credit',
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(PurchaseStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: status.color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
