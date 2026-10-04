import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/inventory/inventory_ledger_entry.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Modal dialog showing the stock movement history and audit trail for a product.
class StockLedgerDialog extends ConsumerWidget {
  final Product product;

  const StockLedgerDialog({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogService = ref.watch(catalogServiceProvider);

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_outlined, color: BillzoColors.primaryBlue, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stock Audit Trail — ${product.name}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Current Stock: ${product.currentStock} units',
                          style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),

            // Ledger Entries
            Expanded(
              child: FutureBuilder<List<InventoryLedgerEntry>>(
                future: catalogService.getStockLedger(product.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: BillzoColors.dangerRed)));
                  }

                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('No stock movements recorded yet.', style: TextStyle(color: BillzoColors.neutralText)),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = entries[index];
                      final isPositive = item.quantityChanged >= 0;
                      final dateFormatted = DateFormat('dd MMM yyyy, hh:mm a').format(item.transactionDate.toLocal());

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isPositive ? BillzoColors.successGreen : BillzoColors.dangerRed).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                                size: 16,
                                color: isPositive ? BillzoColors.successGreen : BillzoColors.dangerRed,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        item.transactionType.replaceAll('_', ' ').toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        dateFormatted,
                                        style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                      ),
                                    ],
                                  ),
                                  if (item.notes != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.notes!,
                                      style: const TextStyle(fontSize: 12, color: BillzoColors.darkSlate),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${isPositive ? '+' : ''}${item.quantityChanged}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: isPositive ? BillzoColors.successGreen : BillzoColors.dangerRed,
                                  ),
                                ),
                                Text(
                                  'Balance: ${item.stockAfter}',
                                  style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
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
