import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:counterday/data/app_store.dart';
import 'package:counterday/ui/invoices.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Invoice edit dialog flow: open edit, add product, cancel, custom product, cancel', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final store = await AppStore.openForTesting(NativeDatabase.memory());
    addTearDown(() => store.close());

    await store.saveProduct({'id': 'cement', 'name': 'Cement Bag', 'price': 350.0, 'unit': 'bag'}, openingStock: 50);

    final invoice = await store.finalizeInvoice(
      lines: [
        {'productId': 'cement', 'name': 'Cement Bag', 'unit': 'bag', 'quantity': 2.0, 'price': 350.0, 'gst': 18.0}
      ],
      customer: {'name': 'Raju', 'phone': '9999999999'},
      discount: {},
      paymentEntries: [{'method': 'Cash', 'amount': 100.0}],
      gstEnabled: false,
      taxInclusive: false,
      interstate: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showInvoice(context, store, invoice),
                  child: const Text('Open Invoice'),
                ),
              ),
            );
          },
        ),
      ),
    );

    // 1. Open showInvoice dialog
    await tester.tap(find.text('Open Invoice'));
    await tester.pumpAndSettle();

    expect(find.text('Edit / Add items'), findsOneWidget);

    // 2. Tap Edit / Add items
    await tester.tap(find.text('Edit / Add items'));
    await tester.pumpAndSettle();

    expect(find.text('Add Product'), findsOneWidget);
    expect(find.text('Custom Product'), findsOneWidget);

    // 3. Tap Add Product
    await tester.tap(find.text('Add Product'));
    await tester.pumpAndSettle();

    expect(find.text('Select product to add'), findsOneWidget);

    // Close Add Product dialog using close icon
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    // 4. Tap Custom Product
    await tester.tap(find.text('Custom Product'));
    await tester.pumpAndSettle();

    expect(find.text('Add custom item'), findsOneWidget);

    // Tap "Cancel" on Custom Product dialog
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    // 5. Tap "Cancel" on Edit Items dialog
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // We should be back on showInvoice dialog
    expect(find.text('Edit / Add items'), findsOneWidget);
  });
}
