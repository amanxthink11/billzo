import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/screens/settings/backup_restore_screen.dart';

/// Screen managing unified business settings, offline media (logo, authorized signature),
/// statutory invoice defaults (terms, notes), and local database backups.
class SettingsScreen extends ConsumerStatefulWidget {
  final Business business;
  final int initialTabIndex;

  const SettingsScreen({
    super.key,
    required this.business,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Logo management
  final TextEditingController _logoPathController = TextEditingController();
  String? _candidateLogoPath;
  String? _logoError;
  bool _isSavingLogo = false;

  // Signature management
  final TextEditingController _signaturePathController = TextEditingController();
  String? _candidateSignaturePath;
  String? _signatureError;
  bool _isSavingSignature = false;

  // Terms and Notes
  final TextEditingController _defaultTermsController = TextEditingController();
  final TextEditingController _defaultNotesController = TextEditingController();
  bool _termsLoaded = false;
  bool _isSavingTerms = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );

    if (widget.business.logoPath != null) {
      _logoPathController.text = widget.business.logoPath!;
      _candidateLogoPath = widget.business.logoPath!;
    }
    if (widget.business.signaturePath != null) {
      _signaturePathController.text = widget.business.signaturePath!;
      _candidateSignaturePath = widget.business.signaturePath!;
    }
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex &&
        widget.initialTabIndex != _tabController.index) {
      _tabController.animateTo(widget.initialTabIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logoPathController.dispose();
    _signaturePathController.dispose();
    _defaultTermsController.dispose();
    _defaultNotesController.dispose();
    super.dispose();
  }

  void _populateDefaults(BusinessSettings? settings) {
    if (!_termsLoaded && settings != null) {
      _defaultTermsController.text = settings.defaultInvoiceTerms ??
          '1. Payment due within 15 days of invoice date.\n2. Goods/Services once billed cannot be cancelled.';
      _defaultNotesController.text =
          settings.defaultInvoiceNotes ?? 'Thank you for your business!';
      _termsLoaded = true;
    }
  }

  Future<String?> _openImageFileDialog(String title) async {
    if (!Platform.isWindows) return null;
    try {
      final script =
          'Add-Type -AssemblyName System.Windows.Forms; '
          '\$d = New-Object System.Windows.Forms.OpenFileDialog; '
          '\$d.Filter = "Image Files (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg|All Files (*.*)|*.*"; '
          '\$d.Title = "$title"; '
          'if (\$d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$d.FileName }';
      final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          return path;
        }
      }
    } catch (e) {
      debugPrint('Error selecting image file: $e');
    }
    return null;
  }

  bool _isValidImageFile(String path) {
    final lower = path.toLowerCase();
    if (!lower.endsWith('.png') && !lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
      return false;
    }
    final file = File(path);
    return file.existsSync() && file.lengthSync() > 0;
  }

  // --- LOGO ACTIONS ---

  Future<void> _handleBrowseLogo() async {
    final path = await _openImageFileDialog('Select Business Logo');
    if (path != null && mounted) {
      setState(() {
        _logoPathController.text = path;
        _candidateLogoPath = path;
        _logoError = null;
      });
    }
  }

  Future<void> _handleSaveLogo(Business currentBusiness) async {
    final path = _logoPathController.text.trim();
    if (path.isEmpty) {
      setState(() => _logoError = 'Please select or enter a valid image file path');
      return;
    }

    if (!_isValidImageFile(path)) {
      setState(() => _logoError = 'File does not exist or is not a valid PNG/JPG image');
      return;
    }

    setState(() {
      _isSavingLogo = true;
      _logoError = null;
    });

    try {
      final pathProv = ref.read(pathProvider);
      final mediaDir = await pathProv.getMediaDirectory();
      final ext = p.extension(path);
      final destPath = p.join(mediaDir, 'logo_${currentBusiness.id}$ext');

      // Copy file offline to media directory
      await File(path).copy(destPath);

      // Update business entity
      final updated = currentBusiness.copyWith(logoPath: destPath);
      await ref.read(activeBusinessProvider.notifier).updateBusiness(updated);

      if (mounted) {
        setState(() {
          _candidateLogoPath = destPath;
          _logoPathController.text = destPath;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business logo saved successfully.'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _logoError = 'Failed to save logo: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingLogo = false);
      }
    }
  }

  Future<void> _handleRemoveLogo(Business currentBusiness) async {
    setState(() => _isSavingLogo = true);
    try {
      final updated = currentBusiness.copyWith(logoPath: null);
      await ref.read(activeBusinessProvider.notifier).updateBusiness(updated);

      if (mounted) {
        setState(() {
          _candidateLogoPath = null;
          _logoPathController.clear();
          _logoError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business logo removed.'),
            backgroundColor: BillzoColors.darkSlate,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _logoError = 'Failed to remove logo: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingLogo = false);
      }
    }
  }

  // --- SIGNATURE ACTIONS ---

  Future<void> _handleBrowseSignature() async {
    final path = await _openImageFileDialog('Select Authorized Signature');
    if (path != null && mounted) {
      setState(() {
        _signaturePathController.text = path;
        _candidateSignaturePath = path;
        _signatureError = null;
      });
    }
  }

  Future<void> _handleSaveSignature(Business currentBusiness) async {
    final path = _signaturePathController.text.trim();
    if (path.isEmpty) {
      setState(() => _signatureError = 'Please select or enter a valid image file path');
      return;
    }

    if (!_isValidImageFile(path)) {
      setState(() => _signatureError = 'File does not exist or is not a valid PNG/JPG image');
      return;
    }

    setState(() {
      _isSavingSignature = true;
      _signatureError = null;
    });

    try {
      final pathProv = ref.read(pathProvider);
      final mediaDir = await pathProv.getMediaDirectory();
      final ext = p.extension(path);
      final destPath = p.join(mediaDir, 'signature_${currentBusiness.id}$ext');

      // Copy file offline to media directory
      await File(path).copy(destPath);

      // Update business entity
      final updated = currentBusiness.copyWith(signaturePath: destPath);
      await ref.read(activeBusinessProvider.notifier).updateBusiness(updated);

      if (mounted) {
        setState(() {
          _candidateSignaturePath = destPath;
          _signaturePathController.text = destPath;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authorized signature saved successfully.'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _signatureError = 'Failed to save signature: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSignature = false);
      }
    }
  }

  Future<void> _handleRemoveSignature(Business currentBusiness) async {
    setState(() => _isSavingSignature = true);
    try {
      final updated = currentBusiness.copyWith(signaturePath: null);
      await ref.read(activeBusinessProvider.notifier).updateBusiness(updated);

      if (mounted) {
        setState(() {
          _candidateSignaturePath = null;
          _signaturePathController.clear();
          _signatureError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authorized signature removed.'),
            backgroundColor: BillzoColors.darkSlate,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _signatureError = 'Failed to remove signature: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSignature = false);
      }
    }
  }

  // --- TERMS & NOTES ACTIONS ---

  Future<void> _handleSaveDefaults(Business currentBusiness) async {
    setState(() => _isSavingTerms = true);
    try {
      final repo = ref.read(businessRepositoryProvider);
      final existing = await repo.getBusinessSettings(currentBusiness.id);

      final updated = (existing != null)
          ? existing.copyWith(
              defaultInvoiceTerms: _defaultTermsController.text.trim(),
              defaultInvoiceNotes: _defaultNotesController.text.trim(),
            )
          : BusinessSettings(
              id: 'settings-${currentBusiness.id}',
              businessId: currentBusiness.id,
              defaultInvoiceTerms: _defaultTermsController.text.trim(),
              defaultInvoiceNotes: _defaultNotesController.text.trim(),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

      await repo.updateBusinessSettings(updated);
      ref.invalidate(businessSettingsProvider(currentBusiness.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Default invoice notes and terms saved successfully.'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save defaults: $e'),
            backgroundColor: BillzoColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingTerms = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeBusinessAsync = ref.watch(activeBusinessProvider);
    final currentBusiness = activeBusinessAsync.value ?? widget.business;

    final settingsAsync = ref.watch(businessSettingsProvider(currentBusiness.id));
    settingsAsync.whenData((s) => _populateDefaults(s));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Settings & Configuration',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: BillzoColors.darkSlate,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage business branding, offline signature, invoice defaults, and local backups.',
                        style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tabs Navigation
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: BillzoColors.border, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: BillzoColors.primaryBlue,
              unselectedLabelColor: BillzoColors.neutralText,
              indicatorColor: BillzoColors.primaryBlue,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              tabs: const [
                Tab(
                  icon: Icon(Icons.storefront_outlined, size: 18),
                  text: 'Business Profile & Defaults',
                ),
                Tab(
                  icon: Icon(Icons.backup_outlined, size: 18),
                  text: 'Backup & Restore',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Profile, Branding & Defaults
                _buildProfileAndDefaultsTab(currentBusiness),

                // Tab 2: Backup & Restore
                BackupRestoreScreen(business: currentBusiness),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAndDefaultsTab(Business currentBusiness) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Business Info Summary Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.business_outlined, color: BillzoColors.primaryBlue, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              currentBusiness.name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (currentBusiness.gstin != null && currentBusiness.gstin!.isNotEmpty)
                                    ? BillzoColors.successGreen.withValues(alpha: 0.1)
                                    : BillzoColors.canvasLight,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: (currentBusiness.gstin != null && currentBusiness.gstin!.isNotEmpty)
                                      ? BillzoColors.successGreen.withValues(alpha: 0.3)
                                      : BillzoColors.border,
                                ),
                              ),
                              child: Text(
                                (currentBusiness.gstin != null && currentBusiness.gstin!.isNotEmpty)
                                    ? 'Registered Regular (GSTIN: ${currentBusiness.gstin})'
                                    : 'Composition / Unregistered',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: (currentBusiness.gstin != null && currentBusiness.gstin!.isNotEmpty)
                                      ? BillzoColors.successGreen
                                      : BillzoColors.neutralText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Phone: ${currentBusiness.phone} | State: ${currentBusiness.stateCode} - ${currentBusiness.stateName}'
                          '${currentBusiness.email != null ? ' | Email: ${currentBusiness.email}' : ''}',
                          style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Row: Logo Management & Authorized Signatory
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo Management Card
              Expanded(
                child: _buildLogoCard(currentBusiness),
              ),
              const SizedBox(width: 20),

              // Authorized Signatory Card
              Expanded(
                child: _buildSignatureCard(currentBusiness),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 3. Default Invoice Terms & Notes Card
          _buildInvoiceDefaultsCard(currentBusiness),
        ],
      ),
    );
  }

  // --- LOGO CARD ---
  Widget _buildLogoCard(Business currentBusiness) {
    final hasLogo = _candidateLogoPath != null && _isValidImageFile(_candidateLogoPath!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.image_outlined, size: 20, color: BillzoColors.primaryBlue),
                const SizedBox(width: 8),
                const Text(
                  'Business Logo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Displayed on A4 tax invoices and print previews. Stored 100% offline and included in backups.',
              style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 16),

            // Logo Preview Box
            Center(
              child: Container(
                width: 140,
                height: 100,
                decoration: BoxDecoration(
                  color: BillzoColors.canvasLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.border),
                ),
                child: hasLogo
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_candidateLogoPath!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: BillzoColors.neutralText),
                          ),
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 32, color: BillzoColors.neutralText),
                          SizedBox(height: 4),
                          Text('No Logo Configured', style: TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // File selection input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _logoPathController,
                    decoration: const InputDecoration(
                      hintText: 'Select image file (.png, .jpg)...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _candidateLogoPath = val.trim();
                        _logoError = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSavingLogo ? null : _handleBrowseLogo,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Browse'),
                ),
              ],
            ),

            if (_logoError != null) ...[
              const SizedBox(height: 8),
              Text(
                _logoError!,
                style: const TextStyle(fontSize: 12, color: BillzoColors.dangerRed),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (currentBusiness.logoPath != null) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: BillzoColors.dangerRed),
                    onPressed: _isSavingLogo ? null : () => _handleRemoveLogo(currentBusiness),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Remove Logo'),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BillzoColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSavingLogo ? null : () => _handleSaveLogo(currentBusiness),
                  icon: _isSavingLogo
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save Logo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- SIGNATURE CARD ---
  Widget _buildSignatureCard(Business currentBusiness) {
    final hasSig = _candidateSignaturePath != null && _isValidImageFile(_candidateSignaturePath!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.draw_outlined, size: 20, color: BillzoColors.primaryBlue),
                const SizedBox(width: 8),
                const Text(
                  'Authorized Signatory',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Displayed above the signature line on A4 invoices. Preserved offline in backups.',
              style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 16),

            // Signature Preview Box
            Center(
              child: Container(
                width: 180,
                height: 100,
                decoration: BoxDecoration(
                  color: BillzoColors.canvasLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.border),
                ),
                child: hasSig
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_candidateSignaturePath!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: BillzoColors.neutralText),
                          ),
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.border_color_outlined, size: 30, color: BillzoColors.neutralText),
                          SizedBox(height: 4),
                          Text('Clean Signature Line (Default)', style: TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // File selection input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _signaturePathController,
                    decoration: const InputDecoration(
                      hintText: 'Select signature image (.png, .jpg)...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _candidateSignaturePath = val.trim();
                        _signatureError = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSavingSignature ? null : _handleBrowseSignature,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Browse'),
                ),
              ],
            ),

            if (_signatureError != null) ...[
              const SizedBox(height: 8),
              Text(
                _signatureError!,
                style: const TextStyle(fontSize: 12, color: BillzoColors.dangerRed),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (currentBusiness.signaturePath != null) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: BillzoColors.dangerRed),
                    onPressed: _isSavingSignature ? null : () => _handleRemoveSignature(currentBusiness),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Remove Signature'),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BillzoColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSavingSignature ? null : () => _handleSaveSignature(currentBusiness),
                  icon: _isSavingSignature
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save Signature'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- DEFAULT INVOICE TERMS & NOTES CARD ---
  Widget _buildInvoiceDefaultsCard(Business currentBusiness) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 20, color: BillzoColors.primaryBlue),
                const SizedBox(width: 8),
                const Text(
                  'Default Invoice Terms & Notes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'These values will pre-populate on every new invoice. You can always edit them for individual invoices before finalization.',
              style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 16),

            // Default Invoice Notes
            const Text(
              'Default Invoice Notes',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _defaultNotesController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g., Thank you for your business!',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Default Terms & Conditions
            const Text(
              'Default Terms & Conditions',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _defaultTermsController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g., Payment due within 15 days of invoice date.\nInterest @ 18% p.a. charged after due date.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BillzoColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSavingTerms ? null : () => _handleSaveDefaults(currentBusiness),
                icon: _isSavingTerms
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 16),
                label: const Text('Save Defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
