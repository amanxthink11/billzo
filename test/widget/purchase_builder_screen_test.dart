import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/screens/purchases/purchase_builder_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-builder',
    name: 'Zenith Retails',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  testWidgets('PurchaseBuilderScreen renders title, supplier selector, item grid, and action buttons', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          partiesListProvider.overrideWith((ref) => Future.value([])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PurchaseBuilderScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('New Purchase Bill'), findsOneWidget);

    // Verify Action Buttons
    expect(find.text('Save Draft'), findsOneWidget);
    expect(find.text('Finalize Purchase'), findsOneWidget);

    // Verify Supplier section
    expect(find.text('Supplier & Invoice Information'), findsOneWidget);
    expect(find.text('Click to select Supplier *'), findsOneWidget);
    expect(find.text('Supplier Invoice # *'), findsOneWidget);

    // Verify Line Items & Add row button
    expect(find.text('Items & Line Totals'), findsOneWidget);
    expect(find.text('Add Row'), findsOneWidget);

    // Verify ITC & Total section
    expect(find.text('Payment & Tax Summary'), findsOneWidget);
    expect(find.text('Total Payable:'), findsOneWidget);
    expect(find.text('Eligible Input GST:'), findsOneWidget);
  });
}
