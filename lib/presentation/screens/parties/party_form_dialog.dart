import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/core/constants/indian_states.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/party/party_validator.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';

/// Modal dialog for creating and editing Customers and Suppliers.
class PartyFormDialog extends ConsumerStatefulWidget {
  final String businessId;
  final Party? partyToEdit;
  final PartyType initialPartyType;

  const PartyFormDialog({
    super.key,
    required this.businessId,
    this.partyToEdit,
    this.initialPartyType = PartyType.customer,
  });

  @override
  ConsumerState<PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends ConsumerState<PartyFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late PartyType _partyType;
  late TextEditingController _nameController;
  late TextEditingController _companyController;
  late TextEditingController _contactPersonController;
  late TextEditingController _phoneController;
  late TextEditingController _altPhoneController;
  late TextEditingController _emailController;
  late TextEditingController _gstinController;
  late TextEditingController _panController;
  late TextEditingController _creditLimitController;
  late TextEditingController _creditDaysController;
  late TextEditingController _openingBalanceController;
  late OpeningBalanceType _openingBalanceType;

  // Billing Address
  late TextEditingController _billingAddress1Controller;
  late TextEditingController _billingAddress2Controller;
  late TextEditingController _billingCityController;
  late TextEditingController _billingPincodeController;
  IndianState? _selectedBillingState;

  // Shipping Address
  bool _sameAsBilling = true;
  late TextEditingController _shippingAddress1Controller;
  late TextEditingController _shippingAddress2Controller;
  late TextEditingController _shippingCityController;
  late TextEditingController _shippingPincodeController;
  IndianState? _selectedShippingState;

  late TextEditingController _notesController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.partyToEdit;
    _partyType = p?.partyType ?? widget.initialPartyType;

    _nameController = TextEditingController(text: p?.name ?? '');
    _companyController = TextEditingController(text: p?.companyName ?? '');
    _contactPersonController = TextEditingController(text: p?.contactPerson ?? '');
    _phoneController = TextEditingController(text: p?.phone ?? '');
    _altPhoneController = TextEditingController(text: p?.alternatePhone ?? '');
    _emailController = TextEditingController(text: p?.email ?? '');
    _gstinController = TextEditingController(text: p?.gstin ?? '');
    _panController = TextEditingController(text: p?.pan ?? '');

    _creditLimitController = TextEditingController(
      text: p != null && p.creditLimitPaise > 0 ? (p.creditLimitPaise / 100).toStringAsFixed(0) : '',
    );
    _creditDaysController = TextEditingController(
      text: p != null && p.creditPeriodDays > 0 ? p.creditPeriodDays.toString() : '',
    );
    _openingBalanceController = TextEditingController(
      text: p != null && p.openingBalancePaise > 0 ? (p.openingBalancePaise / 100).toStringAsFixed(0) : '',
    );
    _openingBalanceType = p?.openingBalanceType ??
        (_partyType == PartyType.supplier ? OpeningBalanceType.toPay : OpeningBalanceType.toReceive);

    _billingAddress1Controller = TextEditingController(text: p?.billingAddressLine1 ?? '');
    _billingAddress2Controller = TextEditingController(text: p?.billingAddressLine2 ?? '');
    _billingCityController = TextEditingController(text: p?.billingCity ?? '');
    _billingPincodeController = TextEditingController(text: p?.billingPincode ?? '');
    if (p?.billingStateCode != null) {
      _selectedBillingState = IndianStates.findByCode(p!.billingStateCode!);
    }

    _shippingAddress1Controller = TextEditingController(text: p?.shippingAddressLine1 ?? '');
    _shippingAddress2Controller = TextEditingController(text: p?.shippingAddressLine2 ?? '');
    _shippingCityController = TextEditingController(text: p?.shippingCity ?? '');
    _shippingPincodeController = TextEditingController(text: p?.shippingPincode ?? '');
    if (p?.shippingStateCode != null) {
      _selectedShippingState = IndianStates.findByCode(p!.shippingStateCode!);
    }

    _sameAsBilling = p == null || (p.shippingAddressLine1 == null && p.shippingCity == null);
    _notesController = TextEditingController(text: p?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _emailController.dispose();
    _gstinController.dispose();
    _panController.dispose();
    _creditLimitController.dispose();
    _creditDaysController.dispose();
    _openingBalanceController.dispose();
    _billingAddress1Controller.dispose();
    _billingAddress2Controller.dispose();
    _billingCityController.dispose();
    _billingPincodeController.dispose();
    _shippingAddress1Controller.dispose();
    _shippingAddress2Controller.dispose();
    _shippingCityController.dispose();
    _shippingPincodeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final creditLimitRupees = double.tryParse(_creditLimitController.text.trim()) ?? 0;
      final creditLimitPaise = (creditLimitRupees * 100).round();

      final creditDays = int.tryParse(_creditDaysController.text.trim()) ?? 0;

      final openingBalanceRupees = double.tryParse(_openingBalanceController.text.trim()) ?? 0;
      final openingBalancePaise = (openingBalanceRupees * 100).round();

      final shippingLine1 = _sameAsBilling ? _billingAddress1Controller.text.trim() : _shippingAddress1Controller.text.trim();
      final shippingLine2 = _sameAsBilling ? _billingAddress2Controller.text.trim() : _shippingAddress2Controller.text.trim();
      final shippingCity = _sameAsBilling ? _billingCityController.text.trim() : _shippingCityController.text.trim();
      final shippingPincode = _sameAsBilling ? _billingPincodeController.text.trim() : _shippingPincodeController.text.trim();
      final shippingState = _sameAsBilling ? _selectedBillingState : _selectedShippingState;

      final party = Party(
        id: widget.partyToEdit?.id ?? '',
        businessId: widget.businessId,
        name: _nameController.text.trim(),
        companyName: _companyController.text.trim().isNotEmpty ? _companyController.text.trim() : null,
        partyType: _partyType,
        contactPerson: _contactPersonController.text.trim().isNotEmpty ? _contactPersonController.text.trim() : null,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        alternatePhone: _altPhoneController.text.trim().isNotEmpty ? _altPhoneController.text.trim() : null,
        email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        gstin: _gstinController.text.trim().isNotEmpty ? _gstinController.text.trim().toUpperCase() : null,
        pan: _panController.text.trim().isNotEmpty ? _panController.text.trim().toUpperCase() : null,
        billingAddressLine1: _billingAddress1Controller.text.trim().isNotEmpty ? _billingAddress1Controller.text.trim() : null,
        billingAddressLine2: _billingAddress2Controller.text.trim().isNotEmpty ? _billingAddress2Controller.text.trim() : null,
        billingCity: _billingCityController.text.trim().isNotEmpty ? _billingCityController.text.trim() : null,
        billingStateCode: _selectedBillingState?.code,
        billingStateName: _selectedBillingState?.name,
        billingPincode: _billingPincodeController.text.trim().isNotEmpty ? _billingPincodeController.text.trim() : null,
        shippingAddressLine1: shippingLine1.isNotEmpty ? shippingLine1 : null,
        shippingAddressLine2: shippingLine2.isNotEmpty ? shippingLine2 : null,
        shippingCity: shippingCity.isNotEmpty ? shippingCity : null,
        shippingStateCode: shippingState?.code,
        shippingStateName: shippingState?.name,
        shippingPincode: shippingPincode.isNotEmpty ? shippingPincode : null,
        creditLimitPaise: creditLimitPaise,
        creditPeriodDays: creditDays,
        openingBalancePaise: widget.partyToEdit?.openingBalancePaise ?? openingBalancePaise,
        openingBalanceType: widget.partyToEdit?.openingBalanceType ?? _openingBalanceType,
        currentBalancePaise: widget.partyToEdit?.currentBalancePaise ?? openingBalancePaise,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        isActive: widget.partyToEdit?.isActive ?? true,
        createdAt: widget.partyToEdit?.createdAt ?? DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final service = ref.read(partyServiceProvider);
      if (widget.partyToEdit == null) {
        await service.createParty(party);
      } else {
        await service.updateParty(party);
      }

      ref.invalidate(partiesListProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.partyToEdit != null;

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
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
                  Icon(
                    _partyType == PartyType.customer ? Icons.person_add_outlined : Icons.local_shipping_outlined,
                    color: BillzoColors.primaryBlue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'Edit Party' : 'Add New ${_partyType.displayName}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 18, color: BillzoColors.dangerRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Scrollable Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Party Type Selector
                      const Text(
                        'Party Type',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<PartyType>(
                        segments: const [
                          ButtonSegment(value: PartyType.customer, label: Text('Customer')),
                          ButtonSegment(value: PartyType.supplier, label: Text('Supplier')),
                          ButtonSegment(value: PartyType.both, label: Text('Customer & Supplier')),
                        ],
                        selected: {_partyType},
                        onSelectionChanged: (set) {
                          setState(() {
                            _partyType = set.first;
                            if (!isEditing && _partyType == PartyType.supplier) {
                              _openingBalanceType = OpeningBalanceType.toPay;
                            } else if (!isEditing && _partyType == PartyType.customer) {
                              _openingBalanceType = OpeningBalanceType.toReceive;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 20),

                      // Section 1: Basic Information
                      _buildSectionTitle('Basic Information'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Party Name *',
                                hintText: 'Full contact / trade name',
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Party name is required';
                                }
                                if (val.trim().length < 2) {
                                  return 'Name must be at least 2 characters';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _companyController,
                              decoration: const InputDecoration(
                                labelText: 'Company Name',
                                hintText: 'Optional business/firm name',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Mobile Phone',
                                hintText: '10-digit number',
                                prefixText: '+91 ',
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  final sanitized = PartyValidator.sanitizePhone(val);
                                  if (sanitized.length != 10 || !RegExp(r'^[6-9][0-9]{9}$').hasMatch(sanitized)) {
                                    return 'Valid 10-digit number required';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _altPhoneController,
                              decoration: const InputDecoration(
                                labelText: 'Alternate Phone',
                                hintText: 'Optional contact number',
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email Address',
                                hintText: 'name@example.com',
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  if (!RegExp(r'^[\w\.\-]+@[\w\-]+(\.[a-zA-Z]{2,})+$').hasMatch(val.trim())) {
                                    return 'Invalid email format';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 2: Statutory & Tax
                      _buildSectionTitle('Statutory & Tax Details'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _gstinController,
                              decoration: const InputDecoration(
                                labelText: 'GSTIN',
                                hintText: '15-digit GST number (e.g. 29ABCDE1234F1Z5)',
                              ),
                              textCapitalization: TextCapitalization.characters,
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  final upper = val.trim().toUpperCase();
                                  if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(upper)) {
                                    return 'Invalid 15-digit GSTIN';
                                  }
                                  if (_selectedBillingState != null && upper.substring(0, 2) != _selectedBillingState!.code) {
                                    return 'State code in GSTIN (${upper.substring(0, 2)}) != billing state (${_selectedBillingState!.code})';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _panController,
                              decoration: const InputDecoration(
                                labelText: 'PAN',
                                hintText: '10-character PAN (e.g. ABCDE1234F)',
                              ),
                              textCapitalization: TextCapitalization.characters,
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(val.trim().toUpperCase())) {
                                    return 'Invalid 10-character PAN';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 3: Billing Address
                      _buildSectionTitle('Billing Address'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _billingAddress1Controller,
                        decoration: const InputDecoration(
                          labelText: 'Address Line 1',
                          hintText: 'Premises, building, street',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _billingCityController,
                              decoration: const InputDecoration(labelText: 'City'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<IndianState>(
                              initialValue: _selectedBillingState,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'State'),
                              items: IndianStates.allStates.map((st) {
                                return DropdownMenuItem(
                                  value: st,
                                  child: Text(
                                    '${st.code} - ${st.name}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedBillingState = val;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _billingPincodeController,
                              decoration: const InputDecoration(labelText: 'PIN Code'),
                              keyboardType: TextInputType.number,
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(val.trim())) {
                                    return 'Invalid 6-digit PIN';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Shipping Address
                      Row(
                        children: [
                          _buildSectionTitle('Shipping Address'),
                          const SizedBox(width: 16),
                          Row(
                            children: [
                              Checkbox(
                                value: _sameAsBilling,
                                onChanged: (val) {
                                  setState(() {
                                    _sameAsBilling = val ?? true;
                                  });
                                },
                              ),
                              const Text('Same as billing address', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                      if (!_sameAsBilling) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _shippingAddress1Controller,
                          decoration: const InputDecoration(labelText: 'Shipping Address Line 1'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _shippingCityController,
                                decoration: const InputDecoration(labelText: 'City'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<IndianState>(
                                initialValue: _selectedShippingState,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'State'),
                                items: IndianStates.allStates.map((st) {
                                  return DropdownMenuItem(
                                    value: st,
                                    child: Text(
                                      '${st.code} - ${st.name}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedShippingState = val;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _shippingPincodeController,
                                decoration: const InputDecoration(labelText: 'PIN Code'),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Section 4: Credit & Balances
                      _buildSectionTitle('Credit & Opening Balance'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _creditLimitController,
                              decoration: const InputDecoration(
                                labelText: 'Credit Limit (₹)',
                                prefixText: '₹ ',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _creditDaysController,
                              decoration: const InputDecoration(
                                labelText: 'Credit Period (Days)',
                                suffixText: 'days',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (!isEditing) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _openingBalanceController,
                                decoration: const InputDecoration(
                                  labelText: 'Opening Balance (₹)',
                                  prefixText: '₹ ',
                                  helperText: 'Initial ledger balance at onboarding',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<OpeningBalanceType>(
                                initialValue: _openingBalanceType,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Balance Direction',
                                  helperText: 'Receivable from customer or Payable to supplier',
                                ),
                                items: OpeningBalanceType.values.map((t) {
                                  return DropdownMenuItem(
                                    value: t,
                                    child: Text(
                                      t.displayName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _openingBalanceType = val;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: BillzoColors.canvasLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BillzoColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined, size: 20, color: BillzoColors.neutralText),
                              const SizedBox(width: 12),
                              Text(
                                'Opening Balance: ₹${(widget.partyToEdit!.openingBalancePaise / 100).toStringAsFixed(2)} '
                                '(${widget.partyToEdit!.openingBalanceType.displayName})',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                'Current: ₹${(widget.partyToEdit!.currentBalancePaise / 100).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: widget.partyToEdit!.openingBalanceType == OpeningBalanceType.toReceive
                                      ? BillzoColors.successGreen
                                      : BillzoColors.dangerRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Notes
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Internal Notes',
                          hintText: 'Customer preferences, terms, or special instructions',
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(isEditing ? 'Save Changes' : 'Create Party'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: BillzoColors.darkSlate,
      ),
    );
  }
}
