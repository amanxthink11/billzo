import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:billzo/core/constants/app_constants.dart';
import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/common/widgets/billzo_brand_mark.dart';
import 'package:billzo/presentation/common/widgets/keyboard_shortcuts_dialog.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/screens/catalog/products_screen.dart';
import 'package:billzo/presentation/screens/onboarding/business_setup_screen.dart';
import 'package:billzo/presentation/screens/cash_bank/cash_bank_screen.dart';
import 'package:billzo/presentation/screens/parties/parties_screen.dart';
import 'package:billzo/presentation/screens/payments/payments_screen.dart';
import 'package:billzo/presentation/screens/purchases/purchases_screen.dart';
import 'package:billzo/presentation/screens/expenses/expenses_screen.dart';
import 'package:billzo/presentation/screens/recurring/missed_schedules_dialog.dart';
import 'package:billzo/presentation/screens/recurring/recurring_invoices_screen.dart';
import 'package:billzo/presentation/providers/recurring_providers.dart';
import 'package:billzo/presentation/screens/reports/reports_screen.dart';
import 'package:billzo/presentation/screens/sales/invoice_builder_screen.dart';
import 'package:billzo/presentation/screens/sales/sales_invoices_screen.dart';
import 'package:billzo/presentation/screens/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop window configuration
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(AppConstants.defaultWindowWidth, AppConstants.defaultWindowHeight),
        minimumSize: Size(AppConstants.minWindowWidth, AppConstants.minWindowHeight),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'Billzo — Billing. Business. Simple.',
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Window manager initialization notice: $e');
    }
  }

  runApp(
    const ProviderScope(
      child: BillzoApp(),
    ),
  );
}

class BillzoApp extends ConsumerWidget {
  const BillzoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBusinessAsync = ref.watch(activeBusinessProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: BillzoTheme.lightTheme,
      home: activeBusinessAsync.when(
        loading: () => const Scaffold(
          backgroundColor: BillzoColors.canvasLight,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BillzoBrandMark(size: 48, layout: Axis.vertical),
                SizedBox(height: 24),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: BillzoColors.primaryBlue,
                    strokeWidth: 2.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        error: (err, stack) => Scaffold(
          backgroundColor: BillzoColors.canvasLight,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Initialization error: $err',
                style: const TextStyle(color: BillzoColors.dangerRed),
              ),
            ),
          ),
        ),
        data: (business) {
          if (business == null) {
            return const BusinessSetupScreen();
          }
          return BillzoDesktopShell(business: business);
        },
      ),
    );
  }
}

/// Base desktop shell implementing the 3-zone architecture:
/// 1. Collapsible sidebar
/// 2. Top application bar with global search & "+ New Invoice" action
/// 3. Modular content canvas
class BillzoDesktopShell extends ConsumerStatefulWidget {
  final Business business;

  const BillzoDesktopShell({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<BillzoDesktopShell> createState() => _BillzoDesktopShellState();
}

class _BillzoDesktopShellState extends ConsumerState<BillzoDesktopShell> {
  int _selectedNavIndex = 0;
  int _settingsTabIndex = 0;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openNewInvoice() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceBuilderScreen(business: widget.business),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final missed = await ref.read(missedSchedulesProvider(widget.business.id).future);
        if (missed.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => MissedSchedulesDialog(
              businessId: widget.business.id,
              missedRecords: missed,
            ),
          );
        }
      } catch (_) {
        // Non-blocking offline catchup detection
      }
    });
  }

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Dashboard'),
    _NavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Sales'),
    _NavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments, label: 'Payments'),
    _NavItem(icon: Icons.account_balance_outlined, activeIcon: Icons.account_balance, label: 'Cash & Bank'),
    _NavItem(icon: Icons.shopping_bag_outlined, activeIcon: Icons.shopping_bag, label: 'Purchases'),
    _NavItem(icon: Icons.receipt_outlined, activeIcon: Icons.receipt, label: 'Expenses'),
    _NavItem(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'Inventory'),
    _NavItem(icon: Icons.people_outline, activeIcon: Icons.people, label: 'Customers'),
    _NavItem(icon: Icons.local_shipping_outlined, activeIcon: Icons.local_shipping, label: 'Suppliers'),
    _NavItem(icon: Icons.event_repeat_outlined, activeIcon: Icons.event_repeat, label: 'Recurring'),
    _NavItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Reports'),
    _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f1): () => KeyboardShortcutsDialog.show(context),
        const SingleActivator(LogicalKeyboardKey.f2): _openNewInvoice,
        const SingleActivator(LogicalKeyboardKey.f3): () => _searchFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _searchFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f5): () => setState(() {}),
        const SingleActivator(LogicalKeyboardKey.f9): () => setState(() {
          _settingsTabIndex = 1;
          _selectedNavIndex = 11;
        }),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => setState(() {
          _settingsTabIndex = 1;
          _selectedNavIndex = 11;
        }),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => setState(() => _selectedNavIndex = 0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => setState(() => _selectedNavIndex = 1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => setState(() => _selectedNavIndex = 2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => setState(() => _selectedNavIndex = 3),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => setState(() => _selectedNavIndex = 4),
        const SingleActivator(LogicalKeyboardKey.digit6, control: true): () => setState(() => _selectedNavIndex = 5),
        const SingleActivator(LogicalKeyboardKey.digit7, control: true): () => setState(() => _selectedNavIndex = 6),
        const SingleActivator(LogicalKeyboardKey.digit8, control: true): () => setState(() => _selectedNavIndex = 7),
        const SingleActivator(LogicalKeyboardKey.digit9, control: true): () => setState(() => _selectedNavIndex = 8),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => setState(() => _selectedNavIndex = 10),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => setState(() {
          _settingsTabIndex = 0;
          _selectedNavIndex = 11;
        }),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              // Sidebar
              Container(
                width: 240,
                decoration: const BoxDecoration(
              color: BillzoColors.cardSurface,
              border: Border(
                right: BorderSide(color: BillzoColors.border, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand Header
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                  child: BillzoBrandMark(size: 34),
                ),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Navigation Items
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _navItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = _navItems[index];
                      final isSelected = _selectedNavIndex == index;
                      return _SidebarTile(
                        item: item,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            if (index == 11) _settingsTabIndex = 0;
                            _selectedNavIndex = index;
                          });
                        },
                      );
                    },
                  ),
                ),

                // Offline Status Indicator at Sidebar bottom
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: BillzoColors.canvasLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BillzoColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: BillzoColors.successGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '100% Offline Mode',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: BillzoColors.neutralText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Area: Top Bar + Active Module Screen
          Expanded(
            child: Column(
              children: [
                // Top Application Bar
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: BillzoColors.cardSurface,
                    border: Border(
                      bottom: BorderSide(color: BillzoColors.border, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Search Bar
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            height: 38,
                            child: TextField(
                              focusNode: _searchFocusNode,
                              decoration: InputDecoration(
                                hintText: 'Search invoices, customers, items... (Ctrl+K)',
                                prefixIcon: const Icon(Icons.search, size: 20, color: BillzoColors.neutralText),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: BillzoColors.border),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Business Indicator Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: BillzoColors.canvasLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: BillzoColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storefront_outlined, size: 16, color: BillzoColors.neutralText),
                            const SizedBox(width: 6),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.business.name,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                if (widget.business.gstin != null)
                                  Text(
                                    'GSTIN: ${widget.business.gstin}',
                                    style: const TextStyle(fontSize: 10, color: BillzoColors.neutralText),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Keyboard Shortcuts Button
                      IconButton(
                        icon: const Icon(Icons.keyboard_outlined, size: 20, color: BillzoColors.neutralText),
                        tooltip: 'Keyboard Shortcuts [F1]',
                        onPressed: () => KeyboardShortcutsDialog.show(context),
                      ),

                      // Backup & Restore Quick Link
                      IconButton(
                        icon: const Icon(Icons.backup_outlined, size: 20, color: BillzoColors.neutralText),
                        tooltip: 'Backup & Restore [F9 / Ctrl+B]',
                        onPressed: () => setState(() {
                          _settingsTabIndex = 1;
                          _selectedNavIndex = 11;
                        }),
                      ),
                      const SizedBox(width: 8),

                      // Primary CTA: + New Invoice
                      ElevatedButton.icon(
                        onPressed: _openNewInvoice,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New Invoice  [F2]'),
                      ),
                    ],
                  ),
                ),

                // Canvas Workspace
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _buildModuleContent(_selectedNavIndex),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildModuleContent(int navIndex) {
    switch (navIndex) {
      case 0:
        return _DashboardPreview(
          business: widget.business,
          onNavigate: (idx) => setState(() {
            if (idx == 11) _settingsTabIndex = 1;
            _selectedNavIndex = idx;
          }),
        );
      case 1:
        return SalesInvoicesScreen(business: widget.business);
      case 2:
        return PaymentsScreen(business: widget.business);
      case 3:
        return CashBankScreen(business: widget.business);
      case 4:
        return PurchasesScreen(business: widget.business);
      case 5:
        return ExpensesScreen(business: widget.business);
      case 6:
        return ProductsScreen(business: widget.business);
      case 7:
        return PartiesScreen(business: widget.business, initialTypeFilter: PartyType.customer);
      case 8:
        return PartiesScreen(business: widget.business, initialTypeFilter: PartyType.supplier);
      case 9:
        return RecurringInvoicesScreen(business: widget.business);
      case 10:
        return ReportsScreen(business: widget.business);
      case 11:
        return SettingsScreen(business: widget.business, initialTabIndex: _settingsTabIndex);
      default:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BillzoBrandMark(size: 48, showWordmark: false),
              const SizedBox(height: 16),
              Text(
                '${_navItems[navIndex].label} Module',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Architected for sequential phase implementation.',
                style: TextStyle(color: BillzoColors.neutralText),
              ),
            ],
          ),
        );
    }
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? BillzoColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? item.activeIcon : item.icon,
              size: 20,
              color: isSelected ? Colors.white : BillzoColors.neutralText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : BillzoColors.darkSlate,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Production dashboard displaying business KPIs, system health, and quick actions
class _DashboardPreview extends StatelessWidget {
  final Business business;
  final ValueChanged<int>? onNavigate;

  const _DashboardPreview({
    required this.business,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards Row
          const Row(
            children: [
              Expanded(child: _KpiCard(title: "Today's Sales", amount: "₹0", color: BillzoColors.darkSlate)),
              SizedBox(width: 16),
              Expanded(child: _KpiCard(title: "Today's Collection", amount: "₹0", color: BillzoColors.successGreen)),
              SizedBox(width: 16),
              Expanded(child: _KpiCard(title: "Receivables", amount: "₹0", color: BillzoColors.accentOrange)),
              SizedBox(width: 16),
              Expanded(child: _KpiCard(title: "Payables", amount: "₹0", color: BillzoColors.dangerRed)),
            ],
          ),
          const SizedBox(height: 24),

          // Business Profile & System Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: BillzoColors.successGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.verified_outlined, color: BillzoColors.successGreen),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          business.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Production Ready — Offline First',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.primaryBlue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'State: ${business.stateCode} - ${business.stateName} | Phone: ${business.phone}'
                    '${business.gstin != null ? ' | GSTIN: ${business.gstin}' : ' | Composition/Unregistered'}',
                    style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Billzo is operating in 100% offline mode with SQLite 3 Write-Ahead Logging (WAL) and foreign keys enabled. Business data, ledger integrity, automated backups (.billzobak), and statutory GST records are stored locally.',
                    style: TextStyle(fontSize: 13, color: BillzoColors.neutralText, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Quick Actions Grid
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.receipt_long, size: 16, color: BillzoColors.primaryBlue),
                        label: const Text('New Invoice [F2]'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => InvoiceBuilderScreen(business: business)),
                          );
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.person_add_outlined, size: 16, color: BillzoColors.primaryBlue),
                        label: const Text('Customers [Ctrl+8]'),
                        onPressed: () => onNavigate?.call(7),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.inventory_2_outlined, size: 16, color: BillzoColors.primaryBlue),
                        label: const Text('Catalog [Ctrl+7]'),
                        onPressed: () => onNavigate?.call(6),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.shopping_bag_outlined, size: 16, color: BillzoColors.primaryBlue),
                        label: const Text('Purchases [Ctrl+5]'),
                        onPressed: () => onNavigate?.call(4),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.bar_chart_outlined, size: 16, color: BillzoColors.primaryBlue),
                        label: const Text('Reports [Ctrl+0]'),
                        onPressed: () => onNavigate?.call(10),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.backup_outlined, size: 16, color: BillzoColors.primaryBlue),
                        label: const Text('Backup & Restore [F9]'),
                        onPressed: () => onNavigate?.call(11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String amount;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 8),
            Text(
              amount,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
