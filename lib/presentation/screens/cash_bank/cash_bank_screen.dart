import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';

/// Screen displaying Cash and Bank liquidity accounts with balance overview and creation flow.
class CashBankScreen extends ConsumerStatefulWidget {
  final Business business;

  const CashBankScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<CashBankScreen> createState() => _CashBankScreenState();
}

class _CashBankScreenState extends ConsumerState<CashBankScreen> {
  void _openAddAccountDialog() async {
    final result = await showDialog<CashBankAccount>(
      context: context,
      builder: (ctx) => _AddAccountDialog(business: widget.business),
    );

    if (result != null) {
      ref.invalidate(cashBankAccountsProvider(widget.business.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account "${result.name}" created successfully.'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(cashBankAccountsProvider(widget.business.id));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cash & Bank Accounts',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: BillzoColors.darkSlate,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Monitor liquidity, physical cash drawers, and bank holding accounts.',
                      style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BillzoColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'Add Account',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _openAddAccountDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Summary KPI Metric Cards
          accountsAsync.maybeWhen(
            data: (accounts) => _buildKpiCards(accounts),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // 3. Accounts Grid Canvas
          Expanded(
            child: accountsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Error loading accounts: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
              ),
              data: (accounts) {
                if (accounts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_outlined, size: 54, color: BillzoColors.neutralText),
                        const SizedBox(height: 12),
                        const Text(
                          'No Holding Accounts Registered',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add your bank accounts or cash drawers to record receipts accurately.',
                          style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.primaryBlue, foregroundColor: Colors.white),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add First Account'),
                          onPressed: _openAddAccountDialog,
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 420,
                    mainAxisExtent: 230,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: accounts.length,
                  itemBuilder: (ctx, i) => _buildAccountCard(accounts[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCards(List<CashBankAccount> accounts) {
    int totalLiquidityPaise = 0;
    int totalCashPaise = 0;
    int totalBankPaise = 0;
    int activeCount = 0;

    for (final acc in accounts) {
      if (acc.isActive) {
        activeCount++;
        totalLiquidityPaise += acc.currentBalancePaise;
        if (acc.isCash) {
          totalCashPaise += acc.currentBalancePaise;
        } else {
          totalBankPaise += acc.currentBalancePaise;
        }
      }
    }

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            'Total Liquidity',
            '₹${Money.fromPaise(totalLiquidityPaise).toIndianRupeeString()}',
            Icons.account_balance_wallet,
            BillzoColors.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'Cash on Hand',
            '₹${Money.fromPaise(totalCashPaise).toIndianRupeeString()}',
            Icons.payments_outlined,
            const Color(0xFF0D9488),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'Bank Balances',
            '₹${Money.fromPaise(totalBankPaise).toIndianRupeeString()}',
            Icons.account_balance,
            const Color(0xFF7C3AED),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'Active Accounts',
            '$activeCount',
            Icons.check_circle_outline,
            BillzoColors.successGreen,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillzoColors.neutralText),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(CashBankAccount account) {
    final isCash = account.isCash;
    final primaryColor = isCash ? const Color(0xFF0D9488) : const Color(0xFF7C3AED);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BillzoColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Type & Default badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(isCash ? Icons.payments_outlined : Icons.account_balance, color: primaryColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      account.accountType.displayName,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: primaryColor),
                    ),
                  ],
                ),
              ),
              if (account.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('DEFAULT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: BillzoColors.primaryBlue)),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Bank Details if applicable
          if (!isCash && (account.bankName != null || account.accountNumber != null)) ...[
            Text(
              '${account.bankName ?? 'Bank'} ${account.accountNumber != null ? '• • • • ${account.accountNumber!.length > 4 ? account.accountNumber!.substring(account.accountNumber!.length - 4) : account.accountNumber}' : ''}',
              style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
            ),
            if (account.ifscCode != null)
              Text('IFSC: ${account.ifscCode}', style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
            const SizedBox(height: 6),
          ],

          const Divider(height: 16, color: BillzoColors.border),

          // Balance Display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Opening Balance', style: TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                    Text(
                      '₹${account.openingBalance.toIndianRupeeString()}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Current Balance', style: TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                    Text(
                      '₹${account.currentBalance.toIndianRupeeString()}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: account.currentBalancePaise >= 0 ? BillzoColors.successGreen : BillzoColors.dangerRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dialog for creating a new Cash or Bank account.
class _AddAccountDialog extends ConsumerStatefulWidget {
  final Business business;

  const _AddAccountDialog({required this.business});

  @override
  ConsumerState<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<_AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ifscController = TextEditingController();
  final _openingBalanceController = TextEditingController(text: '0');

  CashBankAccountType _accountType = CashBankAccountType.bank;
  bool _isDefault = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _ifscController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final now = DateTime.now().toUtc();
    final double opBal = double.tryParse(_openingBalanceController.text.trim()) ?? 0.0;
    final int opBalPaise = Money.fromRupees(opBal).paise;

    final newAccount = CashBankAccount(
      id: const Uuid().v4(),
      businessId: widget.business.id,
      name: _nameController.text.trim(),
      accountType: _accountType,
      bankName: _accountType == CashBankAccountType.bank ? _bankNameController.text.trim() : null,
      accountNumber: _accountType == CashBankAccountType.bank ? _accountNumberController.text.trim() : null,
      ifscCode: _accountType == CashBankAccountType.bank ? _ifscController.text.trim().toUpperCase() : null,
      openingBalancePaise: opBalPaise,
      currentBalancePaise: opBalPaise,
      isDefault: _isDefault,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final service = ref.read(paymentServiceProvider);
      final created = await service.createCashBankAccount(newAccount);
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Add Cash / Bank Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.3)),
                    ),
                    child: Text(_errorMessage!, style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                ],

                // Account Type Selector
                SegmentedButton<CashBankAccountType>(
                  segments: const [
                    ButtonSegment(value: CashBankAccountType.bank, label: Text('Bank Account'), icon: Icon(Icons.account_balance)),
                    ButtonSegment(value: CashBankAccountType.cash, label: Text('Cash Drawer'), icon: Icon(Icons.payments)),
                  ],
                  selected: {_accountType},
                  onSelectionChanged: (set) => setState(() => _accountType = set.first),
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: _accountType == CashBankAccountType.bank ? 'Account Nickname *' : 'Cash Drawer Name *',
                    hintText: _accountType == CashBankAccountType.bank ? 'e.g., HDFC Current Account' : 'e.g., Main Register Drawer',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
                ),
                const SizedBox(height: 12),

                // If Bank: Bank Name, Account Number, IFSC
                if (_accountType == CashBankAccountType.bank) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _bankNameController,
                          decoration: const InputDecoration(
                            labelText: 'Bank Name',
                            hintText: 'e.g., HDFC Bank',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _ifscController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'IFSC Code',
                            hintText: 'HDFC0001234',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Account Number',
                      hintText: 'e.g., 50200012345678',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Opening Balance
                TextFormField(
                  controller: _openingBalanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Opening Balance (₹)',
                    hintText: '0.00',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = double.tryParse(v.trim());
                    if (n == null) return 'Enter a valid amount';
                    if (n < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Default Checkbox
                CheckboxListTile(
                  title: const Text('Set as default receiving account', style: TextStyle(fontSize: 13)),
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.primaryBlue, foregroundColor: Colors.white),
                      onPressed: _isSaving ? null : _submit,
                      child: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save Account'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
