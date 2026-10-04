import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/backup/backup_manifest.dart';
import 'package:billzo/domain/backup/backup_record.dart';
import 'package:billzo/domain/backup/restore_result.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/presentation/providers/backup_providers.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Screen managing local `.billzobak` backups, verified restorations, and auto-backup settings.
class BackupRestoreScreen extends ConsumerStatefulWidget {
  final Business business;

  const BackupRestoreScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  // Backup Creation State
  bool _isCreatingBackup = false;
  File? _lastCreatedBackup;

  // Restore State
  final TextEditingController _restorePathController = TextEditingController();
  bool _isValidating = false;
  bool _isRestoring = false;
  BackupManifest? _inspectedManifest;
  String? _validationError;
  RestoreResult? _lastRestoreResult;
  bool _allowCrossBusiness = false;

  // Auto Backup Settings State
  bool _autoBackupEnabled = true;
  int _autoBackupIntervalDays = 1;
  final TextEditingController _customDirController = TextEditingController();
  bool _settingsLoaded = false;
  bool _isSavingSettings = false;

  @override
  void dispose() {
    _restorePathController.dispose();
    _customDirController.dispose();
    super.dispose();
  }

  void _initSettings(BusinessSettings? settings) {
    if (!_settingsLoaded && settings != null) {
      _autoBackupEnabled = settings.autoBackupEnabled;
      _autoBackupIntervalDays = settings.autoBackupIntervalDays;
      _customDirController.text = settings.backupDirectoryPath ?? '';
      _settingsLoaded = true;
    }
  }

  Future<void> _handleCreateBackup() async {
    setState(() {
      _isCreatingBackup = true;
      _lastCreatedBackup = null;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final customPath = _customDirController.text.trim().isNotEmpty
          ? _customDirController.text.trim()
          : null;

      final backupFile = await backupService.createBackup(
        business: widget.business,
        customDestinationPath: customPath,
        backupType: 'MANUAL',
      );

      ref.invalidate(backupHistoryProvider(widget.business.id));
      ref.invalidate(localBackupFilesProvider);

      if (mounted) {
        setState(() {
          _lastCreatedBackup = backupFile;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup created successfully: ${backupFile.path}'),
            backgroundColor: BillzoColors.successGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create backup: $e'),
            backgroundColor: BillzoColors.dangerRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingBackup = false;
        });
      }
    }
  }

  Future<void> _handleInspectBackup([String? explicitPath]) async {
    final path = explicitPath ?? _restorePathController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or specify a .billzobak backup file path.'),
          backgroundColor: BillzoColors.warningAmber,
        ),
      );
      return;
    }

    _restorePathController.text = path;
    setState(() {
      _isValidating = true;
      _inspectedManifest = null;
      _validationError = null;
      _lastRestoreResult = null;
    });

    try {
      final restoreService = ref.read(restoreServiceProvider);
      final manifest = await restoreService.inspectAndValidateBackup(path);
      if (mounted) {
        setState(() {
          _inspectedManifest = manifest;
          _allowCrossBusiness = manifest.businessId == widget.business.id;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validationError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  Future<void> _confirmAndExecuteRestore() async {
    if (_inspectedManifest == null) return;

    final isCrossBusiness = _inspectedManifest!.businessId != widget.business.id;
    if (isCrossBusiness && !_allowCrossBusiness) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cross-business restore must be explicitly confirmed before proceeding.'),
          backgroundColor: BillzoColors.warningAmber,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: BillzoColors.dangerRed, size: 28),
            SizedBox(width: 10),
            Text('Confirm Database Restore'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your current data will be replaced by the selected backup.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: BillzoColors.dangerRed),
            ),
            const SizedBox(height: 12),
            Text(
              'A mandatory pre-restore safety snapshot will be created automatically before any files are touched. '
              'If any step fails, the system will safely rollback to your current data.',
              style: TextStyle(fontSize: 13, color: BillzoColors.darkSlate),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BillzoColors.canvasLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BillzoColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backup Business: ${_inspectedManifest!.businessName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('Invoices in Backup: ${_inspectedManifest!.totalInvoices}', style: const TextStyle(fontSize: 12)),
                  Text('Customers in Backup: ${_inspectedManifest!.totalCustomers}', style: const TextStyle(fontSize: 12)),
                  Text('Products in Backup: ${_inspectedManifest!.totalProducts}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BillzoColors.dangerRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Proceed with Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      final restoreService = ref.read(restoreServiceProvider);
      final result = await restoreService.executeRestore(
        backupFilePath: _restorePathController.text.trim(),
        currentBusinessId: widget.business.id,
        allowCrossBusiness: _allowCrossBusiness,
      );

      // Invalidate relevant providers after database swap
      ref.invalidate(activeBusinessProvider);
      ref.invalidate(backupHistoryProvider(widget.business.id));

      if (mounted) {
        setState(() {
          _lastRestoreResult = result;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: BillzoColors.successGreen, size: 28),
                SizedBox(width: 10),
                Text('Restore Successful'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Database restored successfully for "${result.manifest.businessName}".',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text('Restored Media Assets: ${result.restoredMediaFilesCount}'),
                const SizedBox(height: 8),
                Text(
                  'Pre-restore safety snapshot safely saved at:\n${result.safetySnapshotPath}',
                  style: TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 28),
                SizedBox(width: 10),
                Text('Restore Failed'),
              ],
            ),
            content: Text(
              e.toString(),
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Future<void> _handleSaveAutoBackupSettings(BusinessSettings settings) async {
    setState(() {
      _isSavingSettings = true;
    });

    try {
      final updatedSettings = settings.copyWith(
        autoBackupEnabled: _autoBackupEnabled,
        autoBackupIntervalDays: _autoBackupIntervalDays,
        backupDirectoryPath: _customDirController.text.trim().isNotEmpty
            ? _customDirController.text.trim()
            : null,
      );

      final repo = ref.read(businessRepositoryProvider);
      await repo.updateBusinessSettings(updatedSettings);
      ref.invalidate(businessSettingsProvider(widget.business.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-backup settings updated successfully.'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update settings: $e'),
            backgroundColor: BillzoColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSettings = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(businessSettingsProvider(widget.business.id));
    final historyAsync = ref.watch(backupHistoryProvider(widget.business.id));
    final localFilesAsync = ref.watch(localBackupFilesProvider);

    settingsAsync.whenData((s) => _initSettings(s));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Local Backup & Restore',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: BillzoColors.darkSlate,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Deterministic, offline-first .billzobak backups with cryptographic SHA-256 verification.',
                        style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  onPressed: () {
                    ref.invalidate(backupHistoryProvider(widget.business.id));
                    ref.invalidate(localBackupFilesProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Top Row: Create Backup & Restore Backup Cards
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card 1: Create Backup
                Expanded(
                  child: _buildCreateBackupCard(),
                ),
                const SizedBox(width: 24),

                // Card 2: Restore Backup
                Expanded(
                  child: _buildRestoreBackupCard(localFilesAsync),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Bottom Row: Auto Backup Settings & Backup History
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Auto Backup Settings
                Expanded(
                  flex: 2,
                  child: _buildAutoBackupCard(settingsAsync),
                ),
                const SizedBox(width: 24),

                // Backup History Table
                Expanded(
                  flex: 3,
                  child: _buildHistoryCard(historyAsync),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateBackupCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BillzoColors.border),
      ),
      color: BillzoColors.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.archive_outlined, color: BillzoColors.primaryBlue, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: const Text(
                    'Create Local Backup (.billzobak)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Generates a complete, verified package containing your active database snapshot, '
              'branding logos/signatures, and cryptographic SHA-256 manifest.',
              style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BillzoColors.canvasLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BillzoColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.business, size: 16, color: BillzoColors.neutralText),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Business: ${widget.business.name}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: BillzoColors.successGreen),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Integrity: SHA-256 Checksum Included',
                          style: TextStyle(fontSize: 12, color: BillzoColors.successGreen),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: BillzoColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _isCreatingBackup
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download, size: 18),
              label: Text(_isCreatingBackup ? 'Creating Snapshot...' : 'Create Backup Now'),
              onPressed: _isCreatingBackup ? null : _handleCreateBackup,
            ),
            if (_lastCreatedBackup != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BillzoColors.successGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: BillzoColors.successGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: BillzoColors.successGreen, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saved: ${_lastCreatedBackup!.path}',
                        style: const TextStyle(fontSize: 11, color: BillzoColors.successGreen, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreBackupCard(AsyncValue<List<File>> localFilesAsync) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BillzoColors.border),
      ),
      color: BillzoColors.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.unarchive_outlined, color: BillzoColors.darkSlate, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: const Text(
                    'Restore from Backup',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Select a .billzobak file to inspect and safely restore. Billzo automatically creates '
              'a safety snapshot before any replacement occurs.',
              style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 14),

            // File selection input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _restorePathController,
                    decoration: InputDecoration(
                      hintText: 'Enter absolute path to .billzobak file',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: BillzoColors.border),
                      ),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BillzoColors.darkSlate,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isValidating || _isRestoring ? null : () => _handleInspectBackup(),
                  child: _isValidating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Inspect'),
                ),
              ],
            ),

            // Quick pick from locally discovered backups
            localFilesAsync.when(
              data: (files) {
                if (files.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: files.take(3).map((f) {
                      final filename = f.uri.pathSegments.last;
                      return ActionChip(
                        label: Text(filename, style: const TextStyle(fontSize: 11)),
                        avatar: const Icon(Icons.insert_drive_file_outlined, size: 14),
                        onPressed: () => _handleInspectBackup(f.path),
                      );
                    }).toList(),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

            // Validation Error Box
            if (_validationError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BillzoColors.dangerRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _validationError!,
                        style: const TextStyle(fontSize: 11, color: BillzoColors.dangerRed),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Last Restore Result Banner
            if (_lastRestoreResult != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BillzoColors.successGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: BillzoColors.successGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: BillzoColors.successGreen, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Restored successfully: ${_lastRestoreResult!.manifest.businessName}',
                        style: const TextStyle(fontSize: 11, color: BillzoColors.successGreen, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Inspected Manifest Preview & Restore Action
            if (_inspectedManifest != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BillzoColors.canvasLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Business: ${_inspectedManifest!.businessName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: BillzoColors.successGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('SHA-256 Verified', style: TextStyle(color: BillzoColors.successGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Invoices: ${_inspectedManifest!.totalInvoices} | Customers: ${_inspectedManifest!.totalCustomers} | Products: ${_inspectedManifest!.totalProducts}',
                      style: TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                    ),
                    Text(
                      'Format v${_inspectedManifest!.formatVersion} | Schema v${_inspectedManifest!.schemaVersion} | Type: ${_inspectedManifest!.backupType}',
                      style: TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                    ),
                    if (_inspectedManifest!.businessId != widget.business.id) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: BillzoColors.warningAmber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: BillzoColors.warningAmber.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: BillzoColors.warningAmber),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Notice: This backup belongs to a different business profile.',
                                style: TextStyle(fontSize: 11, color: BillzoColors.darkSlate),
                              ),
                            ),
                            Checkbox(
                              value: _allowCrossBusiness,
                              onChanged: (val) {
                                setState(() {
                                  _allowCrossBusiness = val ?? false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BillzoColors.dangerRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isRestoring
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.restore, size: 18),
                label: Text(_isRestoring ? 'Restoring Database...' : 'Restore This Backup'),
                onPressed: _isRestoring ? null : _confirmAndExecuteRestore,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAutoBackupCard(AsyncValue<BusinessSettings?> settingsAsync) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BillzoColors.border),
      ),
      color: BillzoColors.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: settingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Error loading settings: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
          data: (settings) {
            if (settings == null) return const Text('No settings found');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule_outlined, color: BillzoColors.primaryBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: const Text(
                        'Auto-Backup Preferences',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Enable Automatic Local Backups', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text(
                            'Periodically creates .billzobak files without interrupting business operations.',
                            style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _autoBackupEnabled,
                      activeThumbColor: BillzoColors.primaryBlue,
                      onChanged: (val) {
                        setState(() {
                          _autoBackupEnabled = val;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text('Backup Frequency:', style: TextStyle(fontSize: 13)),
                    DropdownButton<int>(
                      isDense: true,
                      value: _autoBackupIntervalDays,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Daily')),
                        DropdownMenuItem(value: 3, child: Text('Every 3 Days')),
                        DropdownMenuItem(value: 7, child: Text('Weekly')),
                        DropdownMenuItem(value: 30, child: Text('Monthly')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _autoBackupIntervalDays = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Custom Backup Folder (Optional):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: _customDirController,
                  decoration: InputDecoration(
                    hintText: 'Leave blank to use default application backups folder',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: BillzoColors.border),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isSavingSettings ? null : () => _handleSaveAutoBackupSettings(settings),
                    child: _isSavingSettings
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Preferences'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHistoryCard(AsyncValue<List<BackupRecord>> historyAsync) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BillzoColors.border),
      ),
      color: BillzoColors.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, color: BillzoColors.darkSlate, size: 20),
                SizedBox(width: 8),
                Text('Backup History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            historyAsync.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              error: (err, _) => Text('Error loading history: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
              data: (records) {
                if (records.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      'No backup records logged yet. Click "Create Backup Now" to make your first backup.',
                      style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                    ),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 16,
                    columns: const [
                      DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Checksum', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                    rows: records.map((rec) {
                      final sizeKb = (rec.fileSizeBytes / 1024).toStringAsFixed(1);
                      final shaShort = rec.sha256Checksum.length > 8
                          ? '${rec.sha256Checksum.substring(0, 8)}...'
                          : rec.sha256Checksum;

                      return DataRow(
                        cells: [
                          DataCell(Text(dateFormat.format(rec.createdAt), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(rec.backupType, style: const TextStyle(fontSize: 11))),
                          DataCell(Text('$sizeKb KB', style: const TextStyle(fontSize: 11))),
                          DataCell(Text(shaShort, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: rec.status == 'VERIFIED'
                                    ? BillzoColors.successGreen.withValues(alpha: 0.12)
                                    : BillzoColors.neutralText.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                rec.status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: rec.status == 'VERIFIED' ? BillzoColors.successGreen : BillzoColors.neutralText,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
