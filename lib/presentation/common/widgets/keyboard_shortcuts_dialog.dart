import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:billzo/core/theme/colors.dart';

/// Desktop dialog displaying comprehensive keyboard shortcut references for Billzo.
class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const KeyboardShortcutsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context, rootNavigator: true).pop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: BillzoColors.cardSurface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.keyboard_outlined, color: BillzoColors.primaryBlue, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Keyboard Shortcuts',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'High-speed desktop ergonomics for counter billing and navigation',
                              style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: BillzoColors.neutralText),
                        tooltip: 'Close [Esc]',
                        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: BillzoColors.border),
                  const SizedBox(height: 16),

                  // Shortcuts Table
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Counter Invoicing & Billing (Speed Workflow)'),
                          const SizedBox(height: 8),
                          _buildShortcutRow('F2', 'New Invoice / Add Line Item in Builder'),
                          _buildShortcutRow('F3', 'Focus Barcode Scanner / Product Search'),
                          _buildShortcutRow('F4', 'Select / Switch Customer in Invoice'),
                          _buildShortcutRow('F10', 'Finalize & Print Invoice'),
                          _buildShortcutRow('Ctrl + S', 'Save Invoice as Draft'),
                          _buildShortcutRow('Ctrl + P', 'Instant Print / Print Preview'),
                          _buildShortcutRow('Escape', 'Cancel / Exit Screen (with safety prompt)'),

                          const SizedBox(height: 20),
                          _buildSectionTitle('Global Desktop Navigation'),
                          const SizedBox(height: 8),
                          _buildShortcutRow('F1', 'Open Keyboard Shortcuts & Help'),
                          _buildShortcutRow('Ctrl + K', 'Focus Global Search Bar'),
                          _buildShortcutRow('F5', 'Refresh Active View'),
                          _buildShortcutRow('Ctrl + B / F9', 'Open Backup & Restore Center'),
                          _buildShortcutRow('Ctrl + 1', 'Dashboard'),
                          _buildShortcutRow('Ctrl + 2', 'Sales & Invoices'),
                          _buildShortcutRow('Ctrl + 3', 'Payments & Receipts'),
                          _buildShortcutRow('Ctrl + 4', 'Cash & Bank Accounts'),
                          _buildShortcutRow('Ctrl + 5', 'Purchases & Inward Bills'),
                          _buildShortcutRow('Ctrl + 6', 'Expense Tracker'),
                          _buildShortcutRow('Ctrl + 7', 'Product & Service Catalog'),
                          _buildShortcutRow('Ctrl + 8', 'Customer Directory'),
                          _buildShortcutRow('Ctrl + 9', 'Supplier Directory'),
                          _buildShortcutRow('Ctrl + 0', 'Reports & Financial Statements'),
                          _buildShortcutRow('Ctrl + ,', 'Settings & System Preferences'),

                          const SizedBox(height: 20),
                          _buildSectionTitle('Modals & Dialogs'),
                          const SizedBox(height: 8),
                          _buildShortcutRow('Escape', 'Close / Dismiss active modal or dialog'),
                          _buildShortcutRow('Enter', 'Confirm primary dialog action'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1, color: BillzoColors.border),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Tip: You can use these shortcuts from any screen.',
                          style: TextStyle(fontSize: 12, color: BillzoColors.neutralText, fontStyle: FontStyle.italic),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BillzoColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('Got it [Esc]', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: BillzoColors.primaryBlue,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildShortcutRow(String keys, String description) {
    final keyParts = keys.split(' ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: keyParts.map((part) {
                if (part == '+' || part == '/') {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: Text(
                      part,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText),
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x10000000),
                        offset: Offset(0, 1),
                        blurRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    part,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: BillzoColors.darkSlate,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: BillzoColors.darkSlate,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
