import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/application/backup/restore_service.dart';
import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/backup/backup_manifest.dart';
import 'package:billzo/domain/backup/backup_record.dart';
import 'package:billzo/domain/backup/restore_result.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/infrastructure/services/backup/backup_service.dart';
import 'package:billzo/presentation/providers/backup_providers.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/screens/settings/backup_restore_screen.dart';

class MockBackupService implements IBackupService {
  bool createBackupCalled = false;

  @override
  Future<File> createBackup({
    required Business business,
    String? customDestinationPath,
    String backupType = 'MANUAL',
  }) async {
    createBackupCalled = true;
    return File('/dummy/backups/billzo_backup_test.billzobak');
  }

  @override
  Future<File?> checkAndRunAutoBackup({
    required Business business,
    required BusinessSettings settings,
  }) async => null;

  @override
  Future<List<File>> getLocalBackupFiles() async => [
    File('/dummy/backups/demo_backup_2026.billzobak'),
  ];
}

class MockRestoreService implements IRestoreService {
  bool restoreExecuted = false;

  @override
  Future<BackupManifest> inspectAndValidateBackup(String backupFilePath) async {
    return BackupManifest(
      formatVersion: 1,
      appVersion: '1.0.0',
      appBuildNumber: 1,
      schemaVersion: 6,
      createdAt: DateTime.now().toUtc(),
      businessId: 'biz-widget-test',
      businessName: 'Zenith Apex Corp',
      databaseSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      totalInvoices: 42,
      totalCustomers: 12,
      totalProducts: 25,
      backupType: 'MANUAL',
    );
  }

  @override
  Future<RestoreResult> executeRestore({
    required String backupFilePath,
    required String currentBusinessId,
    bool allowCrossBusiness = false,
  }) async {
    restoreExecuted = true;
    final manifest = await inspectAndValidateBackup(backupFilePath);
    return RestoreResult(
      manifest: manifest,
      safetySnapshotPath: '/dummy/backups/pre_restore_safety_backup_123.db',
      restoredAt: DateTime.now().toUtc(),
      restoredMediaFilesCount: 2,
    );
  }
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-test',
    name: 'Zenith Apex Corp',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final testSettings = BusinessSettings(
    id: 'settings-1',
    businessId: testBiz.id,
    autoBackupEnabled: true,
    autoBackupIntervalDays: 1,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final testRecords = [
    BackupRecord(
      id: 'rec-1',
      businessId: testBiz.id,
      filePath: '/dummy/backups/billzo_backup_rec1.billzobak',
      fileSizeBytes: 20480, // 20 KB
      sha256Checksum: 'abcdef1234567890',
      backupType: 'MANUAL',
      databaseVersion: 6,
      createdAt: DateTime.now().toUtc(),
      status: 'VERIFIED',
    ),
  ];

  late MockBackupService mockBackupService;
  late MockRestoreService mockRestoreService;

  setUp(() {
    mockBackupService = MockBackupService();
    mockRestoreService = MockRestoreService();
  });

  testWidgets('BackupRestoreScreen renders cards, preview, and handles backup and restore workflows', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(mockBackupService),
          restoreServiceProvider.overrideWithValue(mockRestoreService),
          businessSettingsProvider(testBiz.id).overrideWith((ref) => Future.value(testSettings)),
          backupHistoryProvider(testBiz.id).overrideWith((ref) => Future.value(testRecords)),
          localBackupFilesProvider.overrideWith((ref) => Future.value([File('/dummy/backups/demo_backup_2026.billzobak')])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: BackupRestoreScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Header & Cards
    expect(find.text('Local Backup & Restore'), findsOneWidget);
    expect(find.text('Create Local Backup (.billzobak)'), findsOneWidget);
    expect(find.text('Restore from Backup'), findsOneWidget);
    expect(find.text('Auto-Backup Preferences'), findsOneWidget);
    expect(find.text('Backup History'), findsOneWidget);

    // 2. Verify Table content
    expect(find.text('20.0 KB'), findsOneWidget);
    expect(find.text('VERIFIED'), findsOneWidget);

    // 3. Test Create Backup Action
    expect(find.text('Create Backup Now'), findsOneWidget);
    await tester.tap(find.text('Create Backup Now'));
    await tester.pumpAndSettle();

    expect(mockBackupService.createBackupCalled, isTrue);
    expect(find.textContaining('Saved: /dummy/backups/billzo_backup_test.billzobak'), findsOneWidget);

    // 4. Test Inspect Action
    final inputField = find.byType(TextField).first;
    await tester.enterText(inputField, '/dummy/backups/sample.billzobak');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inspect'));
    await tester.pumpAndSettle();

    // Verify Manifest Preview
    expect(find.text('Business: Zenith Apex Corp'), findsWidgets);
    expect(find.text('SHA-256 Verified'), findsOneWidget);
    expect(find.textContaining('Invoices: 42 | Customers: 12 | Products: 25'), findsOneWidget);

    // 5. Test Restore Confirmation Dialog
    expect(find.text('Restore This Backup'), findsOneWidget);
    await tester.tap(find.text('Restore This Backup'));
    await tester.pumpAndSettle();

    // Confirm dialog warning
    expect(find.text('Confirm Database Restore'), findsOneWidget);
    expect(find.text('Your current data will be replaced by the selected backup.'), findsOneWidget);
    expect(find.text('Proceed with Restore'), findsOneWidget);

    // Click Proceed with Restore
    await tester.tap(find.text('Proceed with Restore'));
    await tester.pumpAndSettle();

    expect(mockRestoreService.restoreExecuted, isTrue);
    expect(find.text('Restore Successful'), findsOneWidget);
  });
}
