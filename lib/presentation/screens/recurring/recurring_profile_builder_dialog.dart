import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/domain/recurring/recurring_invoice_validator.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/recurring_providers.dart';
import 'package:billzo/presentation/screens/sales/customer_select_dialog.dart';
import 'package:billzo/presentation/screens/sales/product_select_dialog.dart';

/// Modal dialog for creating or updating a recurring invoice profile.
class RecurringProfileBuilderDialog extends ConsumerStatefulWidget {
  final String businessId;
  final RecurringInvoice? existingProfile;

  const RecurringProfileBuilderDialog({
    super.key,
    required this.businessId,
    this.existingProfile,
  });

  @override
  ConsumerState<RecurringProfileBuilderDialog> createState() =>
      _RecurringProfileBuilderDialogState();
}

class _RecurringProfileBuilderDialogState
    extends ConsumerState<RecurringProfileBuilderDialog> {
  static const _uuid = Uuid();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  Party? _selectedCustomer;
  late RecurringFrequency _frequency;
  late DateTime _startDate;
  DateTime? _endDate;
  late bool _autoSendEmail;
  late bool _generateAsDraft;
  List<RecurringInvoiceItem> _items = [];
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final profile = widget.existingProfile;
    _nameController = TextEditingController(text: profile?.profileName ?? '');
    _frequency = profile?.frequency ?? RecurringFrequency.monthly;
    _startDate = profile?.startDate ?? DateTime.now();
    _endDate = profile?.endDate;
    _autoSendEmail = profile?.autoSendEmail ?? false;
    _generateAsDraft = profile?.generateAsDraft ?? false;

    if (profile != null) {
      _items = List.from(profile.items);
      if (profile.customerId.isNotEmpty) {
        _loadCustomer(profile.customerId);
      }
    }
  }

  Future<void> _loadCustomer(String customerId) async {
    final partyRepo = ref.read(partyRepositoryProvider);
    final party = await partyRepo.getPartyById(customerId);
    if (party != null && mounted) {
      setState(() => _selectedCustomer = party);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  int get _calculatedTotalAmountPaise =>
      _items.fold<int>(0, (sum, i) => sum + i.taxableAmountPaise);

  Future<void> _pickCustomer() async {
    final customer = await showDialog<Party>(
      context: context,
      builder: (ctx) => CustomerSelectDialog(businessId: widget.businessId),
    );
    if (customer != null && mounted) {
      setState(() => _selectedCustomer = customer);
    }
  }

  Future<void> _pickProduct() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (ctx) => ProductSelectDialog(businessId: widget.businessId),
    );
    if (product != null && mounted) {
      _addItemForProduct(product);
    }
  }

  void _addItemForProduct(Product product) {
    const qty = 1;
    final ratePaise = product.sellingPricePaise;
    final now = DateTime.now();

    final newItem = RecurringInvoiceItem(
      id: _uuid.v4(),
      recurringInvoiceId: widget.existingProfile?.id ?? '',
      productId: product.id,
      taxRateId: product.taxRateId ?? '',
      productName: product.name,
      hsnSac: product.hsnSacCode,
      quantity: qty,
      unitCode: 'NOS',
      ratePaise: ratePaise,
      discountPaise: 0,
      createdAt: now,
      updatedAt: now,
    );

    setState(() => _items.add(newItem));
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      setState(() => _errorMessage = 'Please select a customer.');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _errorMessage = 'Please add at least one line item.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final profileId = widget.existingProfile?.id ?? _uuid.v4();
      final nextRun = widget.existingProfile?.nextRunDate ?? _startDate;

      final updatedItems = _items
          .map((i) => RecurringInvoiceItem(
                id: i.id.isEmpty ? _uuid.v4() : i.id,
                recurringInvoiceId: profileId,
                productId: i.productId,
                taxRateId: i.taxRateId,
                productName: i.productName,
                hsnSac: i.hsnSac,
                quantity: i.quantity,
                unitCode: i.unitCode,
                ratePaise: i.ratePaise,
                discountPaise: i.discountPaise,
                createdAt: i.createdAt,
                updatedAt: now,
              ))
          .toList();

      final profile = RecurringInvoice(
        id: profileId,
        businessId: widget.businessId,
        customerId: _selectedCustomer!.id,
        customerName: _selectedCustomer!.name,
        customerPhone: _selectedCustomer!.phone,
        customerGstin: _selectedCustomer!.gstin,
        profileName: _nameController.text.trim(),
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        nextRunDate: nextRun,
        lastRunDate: widget.existingProfile?.lastRunDate,
        status: widget.existingProfile?.status ?? RecurringInvoiceStatus.active,
        autoGenerate: _autoSendEmail,
        requireReview: _generateAsDraft,
        items: updatedItems,
        createdAt: widget.existingProfile?.createdAt ?? now,
        updatedAt: now,
      );

      final errors = RecurringInvoiceValidator.validate(profile);
      if (errors.isNotEmpty) {
        setState(() {
          _isSaving = false;
          _errorMessage = errors.join('\n');
        });
        return;
      }

      final service = ref.read(recurringInvoiceServiceProvider);
      if (widget.existingProfile == null) {
        await service.createProfile(profile);
      } else {
        await service.updateProfile(profile);
      }

      ref.invalidate(recurringInvoicesProvider(widget.businessId));
      ref.invalidate(missedSchedulesProvider(widget.businessId));

      if (mounted) {
        Navigator.of(context).pop(profile);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Error saving recurring profile: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.existingProfile == null
                ? 'New Recurring Invoice Profile'
                : 'Edit Recurring Profile',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                          color: BillzoColors.dangerRed, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Row 1: Profile Name & Customer
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Profile Name *',
                          hintText: 'e.g. Monthly Maintenance Retainer',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Profile name is required';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _pickCustomer,
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: BillzoColors.neutralBorder),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  color: BillzoColors.primaryBlue),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _selectedCustomer?.name ??
                                      'Select Customer *',
                                  style: TextStyle(
                                    fontWeight: _selectedCustomer != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _selectedCustomer != null
                                        ? BillzoColors.darkSlate
                                        : BillzoColors.neutralText,
                                  ),
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Row 2: Frequency & Dates
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<RecurringFrequency>(
                        initialValue: _frequency,
                        decoration: const InputDecoration(
                          labelText: 'Frequency *',
                          border: OutlineInputBorder(),
                        ),
                        items: RecurringFrequency.values.map((f) {
                          return DropdownMenuItem(
                            value: f,
                            child: Text(f.displayName),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _frequency = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2040),
                          );
                          if (date != null) {
                            setState(() {
                              _startDate = date;
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Date *',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(dateFormat.format(_startDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _endDate ?? _startDate.add(const Duration(days: 365)),
                            firstDate: _startDate,
                            lastDate: DateTime(2040),
                          );
                          if (date != null) {
                            setState(() => _endDate = date);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'End Date (Optional)',
                            border: const OutlineInputBorder(),
                            suffixIcon: _endDate != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => setState(() => _endDate = null),
                                  )
                                : null,
                          ),
                          child: Text(_endDate != null
                              ? dateFormat.format(_endDate!)
                              : 'No Expiry'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Row 3: Options (Draft toggle, Auto-email)
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        value: _generateAsDraft,
                        title: const Text('Generate as Draft',
                            style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                            'Hold invoice for manual review before finalization',
                            style: TextStyle(fontSize: 12)),
                        onChanged: (val) =>
                            setState(() => _generateAsDraft = val ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        value: _autoSendEmail,
                        title: const Text('Auto-email Notification',
                            style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                            'Notify customer upon cycle execution',
                            style: TextStyle(fontSize: 12)),
                        onChanged: (val) =>
                            setState(() => _autoSendEmail = val ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Line Items Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recurring Line Items',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    ElevatedButton.icon(
                      onPressed: _pickProduct,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Product / Service'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BillzoColors.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_items.isEmpty)
                  Container(
                    height: 100,
                    alignment: Center(
                      child: Text(
                        'No line items added yet. Click "Add Product / Service" above.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ).alignment,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: BillzoColors.neutralBorder),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: BillzoColors.neutralBorder),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(4),
                        1: FlexColumnWidth(2),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(2),
                        4: FlexColumnWidth(1),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Item',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Qty',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Rate',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Total',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(''),
                            ),
                          ],
                        ),
                        ..._items.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(item.productName),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text('${item.quantity} ${item.unitCode}'),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                    Money.fromPaise(item.ratePaise).formatted),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                    item.taxableAmount.formatted,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: BillzoColors.dangerRed),
                                onPressed: () {
                                  setState(() => _items.removeAt(idx));
                                },
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: BillzoColors.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Profile Total / Cycle: ${Money.fromPaise(_calculatedTotalAmountPaise).formatted}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BillzoColors.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: BillzoColors.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.existingProfile == null
                  ? 'Create Profile'
                  : 'Save Changes'),
        ),
      ],
    );
  }
}
