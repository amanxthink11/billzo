import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/constants/indian_states.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/core/theme/typography.dart';
import 'package:billzo/domain/business/business_validator.dart';
import 'package:billzo/presentation/common/widgets/billzo_brand_mark.dart';
import 'package:billzo/presentation/providers/business_provider.dart';

/// First-run onboarding screen guiding the merchant through initial business profile creation.
class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  ConsumerState<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form Controllers
  final _nameController = TextEditingController();
  final _tradeNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _gstinController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _upiController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _bankIfscController = TextEditingController();

  IndianState? _selectedState;
  bool _hasGst = false;
  bool _showBanking = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default to Maharashtra (27) or Delhi (07)
    _selectedState = IndianStates.findByCode('27') ?? IndianStates.all.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tradeNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _gstinController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _upiController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    _bankIfscController.dispose();
    super.dispose();
  }

  void _onGstinChanged(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.length >= 2) {
      final stateCode = trimmed.substring(0, 2);
      final matchedState = IndianStates.findByCode(stateCode);
      if (matchedState != null && matchedState != _selectedState) {
        setState(() {
          _selectedState = matchedState;
        });
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final state = _selectedState;

    if (state == null) {
      setState(() {
        _errorMessage = 'Please select your business state';
      });
      return;
    }

    final gstin = _hasGst ? _gstinController.text.trim().toUpperCase() : null;
    final email = _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null;
    final pincode = _pincodeController.text.trim().isNotEmpty ? _pincodeController.text.trim() : null;
    final bankIfsc = _bankIfscController.text.trim().isNotEmpty ? _bankIfscController.text.trim().toUpperCase() : null;
    final upiId = _upiController.text.trim().isNotEmpty ? _upiController.text.trim() : null;

    // Strict Domain Validation
    final validation = BusinessValidator.validate(
      name: name,
      phone: phone,
      stateCode: state.code,
      email: email,
      gstin: gstin,
      pincode: pincode,
      bankIfsc: bankIfsc,
      upiId: upiId,
    );

    if (!validation.isValid) {
      setState(() {
        _errorMessage = validation.firstError;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(activeBusinessProvider.notifier).setupBusiness(
        name: name,
        tradeName: _tradeNameController.text.trim().isNotEmpty ? _tradeNameController.text.trim() : null,
        phone: phone,
        email: email,
        gstin: gstin,
        stateCode: state.code,
        stateName: state.name,
        addressLine1: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        city: _cityController.text.trim().isNotEmpty ? _cityController.text.trim() : null,
        pincode: pincode,
        upiId: upiId,
        bankName: _bankNameController.text.trim().isNotEmpty ? _bankNameController.text.trim() : null,
        bankAccountNumber: _bankAccountController.text.trim().isNotEmpty ? _bankAccountController.text.trim() : null,
        bankIfsc: bankIfsc,
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('ArgumentError: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillzoColors.canvasLight,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: BillzoColors.border, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header & Brand
                      Center(
                        child: Column(
                          children: [
                            const BillzoBrandMark(size: 48, layout: Axis.vertical),
                            const SizedBox(height: 16),
                            const Text(
                              'Welcome to Billzo',
                              style: BillzoTypography.headline1,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Set up your business profile to get started with offline billing.',
                              style: TextStyle(fontSize: 14, color: BillzoColors.neutralText),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Divider(height: 1),
                      const SizedBox(height: 24),

                      // Error banner if any
                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Section 1: Business Information
                      const Text(
                        '1. Business Details',
                        style: BillzoTypography.headline2,
                      ),
                      const SizedBox(height: 16),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildTextField(
                              controller: _nameController,
                              label: 'Business Name *',
                              hint: 'e.g. ABC Enterprises',
                              prefixIcon: Icons.store_outlined,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Business name is required';
                                if (v.trim().length < 2) return 'At least 2 characters';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              controller: _phoneController,
                              label: 'Phone Number *',
                              hint: '10-digit mobile',
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Phone is required';
                                if (v.trim().length != 10) return 'Enter 10 digits';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _tradeNameController,
                              label: 'Trade / Brand Name (Optional)',
                              hint: 'e.g. ABC Store',
                              prefixIcon: Icons.branding_watermark_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _emailController,
                              label: 'Email (Optional)',
                              hint: 'contact@business.com',
                              prefixIcon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 2: GST & Location
                      const Text(
                        '2. Tax & Location',
                        style: BillzoTypography.headline2,
                      ),
                      const SizedBox(height: 12),

                      // GST Toggle
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: BillzoColors.hoverSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: BillzoColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.receipt_outlined, color: BillzoColors.primaryBlue, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  'My Business is GST Registered',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ],
                            ),
                            Switch(
                              value: _hasGst,
                              activeThumbColor: BillzoColors.primaryBlue,
                              onChanged: (val) {
                                setState(() {
                                  _hasGst = val;
                                  if (!val) {
                                    _gstinController.clear();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_hasGst) ...[
                        _buildTextField(
                          controller: _gstinController,
                          label: 'GSTIN (15 characters) *',
                          hint: '27AAAAA0000A1Z5',
                          prefixIcon: Icons.verified_user_outlined,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: _onGstinChanged,
                          validator: (v) {
                            if (_hasGst) {
                              if (v == null || v.trim().isEmpty) return 'GSTIN is required when registered';
                              if (v.trim().length != 15) return 'GSTIN must be exactly 15 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'State / Place of Supply *',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<IndianState>(
                                  key: ValueKey(_selectedState?.code),
                                  initialValue: _selectedState,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    prefixIcon: Icon(Icons.map_outlined, size: 20, color: BillzoColors.neutralText),
                                  ),
                                  items: IndianStates.all.map((state) {
                                    return DropdownMenuItem<IndianState>(
                                      value: state,
                                      child: Text(
                                        '${state.code} - ${state.name}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (state) {
                                    setState(() {
                                      _selectedState = state;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              controller: _cityController,
                              label: 'City',
                              hint: 'e.g. Mumbai',
                              prefixIcon: Icons.location_city_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              controller: _pincodeController,
                              label: 'PIN Code',
                              hint: '6 digits',
                              prefixIcon: Icons.pin_drop_outlined,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: _addressController,
                        label: 'Address Line',
                        hint: 'Shop / Office / Street address',
                        prefixIcon: Icons.home_work_outlined,
                      ),
                      const SizedBox(height: 24),

                      // Section 3: Optional Banking Details
                      InkWell(
                        onTap: () {
                          setState(() {
                            _showBanking = !_showBanking;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                _showBanking ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                color: BillzoColors.primaryBlue,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '3. Bank & UPI Details (Optional)',
                                style: BillzoTypography.headline2,
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_showBanking) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _upiController,
                                label: 'UPI ID for QR Code',
                                hint: 'e.g. merchant@upi',
                                prefixIcon: Icons.qr_code_2_outlined,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                controller: _bankNameController,
                                label: 'Bank Name',
                                hint: 'e.g. HDFC Bank',
                                prefixIcon: Icons.account_balance_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _bankAccountController,
                                label: 'Bank Account Number',
                                hint: 'Account number',
                                prefixIcon: Icons.numbers_outlined,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                controller: _bankIfscController,
                                label: 'IFSC Code',
                                hint: 'e.g. HDFC0001234',
                                prefixIcon: Icons.password_outlined,
                                textCapitalization: TextCapitalization.characters,
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 36),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BillzoColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Save Business & Get Started',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          validator: validator,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(prefixIcon, size: 18, color: BillzoColors.neutralText),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
