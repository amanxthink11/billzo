import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/main.dart';
import 'package:billzo/presentation/providers/business_provider.dart';

void main() {
  testWidgets('First-run launches onboarding when no business is configured', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => _MockActiveBusinessNotifier(null)),
        ],
        child: const BillzoApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Welcome to Billzo'), findsOneWidget);
    expect(find.text('Save Business & Get Started'), findsOneWidget);
  });

  testWidgets('Subsequent launch opens desktop shell with existing business name', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockBusiness = Business(
      id: 'biz-001',
      name: 'Sharma Electronics',
      phone: '9820011223',
      stateCode: '27',
      stateName: 'Maharashtra',
      gstin: '27ABCDE1234F1Z5',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => _MockActiveBusinessNotifier(mockBusiness)),
        ],
        child: const BillzoApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Sharma Electronics'), findsWidgets);
    expect(find.text('GSTIN: 27ABCDE1234F1Z5'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('New Invoice  [F2]'), findsOneWidget);
  });
}

class _MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business? _initial;
  _MockActiveBusinessNotifier(this._initial);

  @override
  Future<Business?> build() async => _initial;
}
