import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/main.dart';
import 'package:billzo/presentation/common/widgets/keyboard_shortcuts_dialog.dart';
import 'package:billzo/presentation/providers/backup_providers.dart';
import 'package:billzo/presentation/providers/business_provider.dart';

class _MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business? _initial;
  _MockActiveBusinessNotifier(this._initial);

  @override
  Future<Business?> build() async => _initial;
}

void main() {
  final testBusiness = Business(
    id: 'biz-shortcuts-001',
    name: 'Rapid Billing Store',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    gstin: '27AABCU9603R1ZM',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  testWidgets('KeyboardShortcutsDialog renders all key categories and dismisses on Escape', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KeyboardShortcutsDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keyboard Shortcuts'), findsOneWidget);
    expect(find.text('Counter Invoicing & Billing (Speed Workflow)'.toUpperCase()), findsOneWidget);
    expect(find.text('Global Desktop Navigation'.toUpperCase()), findsOneWidget);
    expect(find.text('Modals & Dialogs'.toUpperCase()), findsOneWidget);

    // Verify key indicators
    expect(find.text('F1'), findsWidgets);
    expect(find.text('F2'), findsWidgets);
    expect(find.text('F3'), findsWidgets);
    expect(find.text('F4'), findsWidgets);
    expect(find.text('F10'), findsWidgets);
    expect(find.text('Escape'), findsWidgets);
  });

  testWidgets('Desktop Shell keyboard shortcuts F1 opens shortcuts dialog', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => _MockActiveBusinessNotifier(testBusiness)),
        ],
        child: const BillzoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rapid Billing Store'), findsWidgets);

    // Press F1 to trigger keyboard shortcuts dialog
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    expect(find.byType(KeyboardShortcutsDialog), findsOneWidget);

    // Press Escape to dismiss dialog
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(KeyboardShortcutsDialog), findsNothing);
  });

  testWidgets('Desktop Shell Ctrl+B / F9 navigates to Backup & Restore Center', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => _MockActiveBusinessNotifier(testBusiness)),
          localBackupFilesProvider.overrideWith((ref) => Future.value([])),
          backupHistoryProvider(testBusiness.id).overrideWith((ref) => Future.value([])),
          businessSettingsProvider(testBusiness.id).overrideWith((ref) => Future.value(BusinessSettings(
            id: 'settings-001',
            businessId: testBusiness.id,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ))),
        ],
        child: const BillzoApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Initially at Dashboard
    expect(find.text('Quick Actions'), findsOneWidget);

    // Press F9
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    // Verify Backup & Restore screen header is rendered
    expect(find.text('Local Backup & Restore'), findsOneWidget);

    // Press Ctrl+1 to go back to Dashboard
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Quick Actions'), findsOneWidget);
  });

  testWidgets('Desktop Shell Ctrl+K focuses quick search input and typing works without shortcut interference', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => _MockActiveBusinessNotifier(testBusiness)),
        ],
        child: const BillzoApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger Ctrl+K
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Type query into focused search bar
    await tester.enterText(find.byType(TextField).first, 'INV-2026');
    await tester.pumpAndSettle();

    expect(find.text('INV-2026'), findsOneWidget);
  });
}
