import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/catalog_providers.dart';
import 'package:billzo/presentation/screens/sales/invoice_builder_screen.dart';

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

  testWidgets('InvoiceBuilderScreen renders header, customer picker, item addition CTA, and action buttons', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          unitsListProvider.overrideWith((ref) => Future.value([])),
          taxRatesListProvider.overrideWith((ref) => Future.value([])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: InvoiceBuilderScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('New Sales Invoice'), findsOneWidget);

    // Verify Customer selector prompt
    expect(find.text('Select or Search Customer [F4]'), findsOneWidget);

    // Verify Add Item button
    expect(find.text('Add Item [F2]'), findsOneWidget);

    // Verify Action Buttons
    expect(find.text('Save Draft'), findsOneWidget);
    expect(find.text('Finalize [F10]'), findsOneWidget);

    // Verify empty invoice item canvas state
    expect(find.text('No items added yet'), findsOneWidget);
    expect(find.text('Click "+ Add Item [F2]" to add goods or services.'), findsOneWidget);

    // Verify Summary section
    expect(find.text('Invoice Summary'), findsOneWidget);
    expect(find.text('Grand Total'), findsOneWidget);
  });
}
