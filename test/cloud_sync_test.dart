import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:counterday/data/app_store.dart';
import 'package:counterday/services/cloud_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('Pairing code generation and parsing roundtrip', () {
    const url = 'https://abcdefghijklmnop.supabase.co';
    const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz';
    const shop = 'SRS AGENCIES';
    const email = 'owner@srsagencies.com';

    final code = CloudSync.createPairingCode(
      url: url,
      anonKey: key,
      shopName: shop,
      email: email,
    );

    expect(code.isNotEmpty, true);

    final parsed = CloudSync.parsePairingCode(code);
    expect(parsed, isNotNull);
    expect(parsed!['url'], url);
    expect(parsed['key'], key);
    expect(parsed['shop'], shop);
    expect(parsed['email'], email);
  });

  test('Pairing code with invalid string returns null gracefully', () {
    expect(CloudSync.parsePairingCode('not-a-valid-code'), isNull);
    expect(CloudSync.parsePairingCode(''), isNull);
  });

  test('Multi-device inventory with image and opening stock replicates via records', () async {
    final deviceA = await AppStore.openForTesting(NativeDatabase.memory());
    final deviceB = await AppStore.openForTesting(NativeDatabase.memory());

    try {
      // Device A adds a product with base64 image and opening stock
      const sampleImageBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      await deviceA.saveProduct({
        'id': 'asian-apex-20l',
        'name': 'Asian Paints Apex 20L',
        'category': 'Paints',
        'price': 4200.0,
        'image': sampleImageBase64,
        'unit': 'bucket',
      }, openingStock: 25);

      expect(deviceA.products.length, 1);
      expect(deviceA.products.first['image'], sampleImageBase64);
      expect(deviceA.stockFor('asian-apex-20l'), 25);

      // Export dirty records from Device A (simulating Supabase push/pull)
      final recordsFromA = deviceA.exportSyncRecords();
      expect(recordsFromA.any((r) => r['kind'] == 'product'), true);
      expect(recordsFromA.any((r) => r['kind'] == 'movement'), true);

      // Device B applies the remote records
      await deviceB.applyRemoteRecords(recordsFromA);

      // Device B should now have the exact product, photo, and stock balance!
      expect(deviceB.products.length, 1);
      expect(deviceB.products.first['name'], 'Asian Paints Apex 20L');
      expect(deviceB.products.first['image'], sampleImageBase64);
      expect(deviceB.stockFor('asian-apex-20l'), 25);
    } finally {
      await deviceA.close();
      await deviceB.close();
    }
  });

  test('Multi-device invoice sale syncs and deducts stock accurately everywhere', () async {
    final deviceA = await AppStore.openForTesting(NativeDatabase.memory());
    final deviceB = await AppStore.openForTesting(NativeDatabase.memory());

    try {
      // Set up identical catalog on both devices
      await deviceA.saveProduct({
        'id': 'cement-50kg',
        'name': 'Ultratech Cement 50kg',
        'price': 380.0,
        'unit': 'bag',
      }, openingStock: 100);

      final initialRecords = deviceA.exportSyncRecords();
      await deviceB.applyRemoteRecords(initialRecords);

      expect(deviceA.stockFor('cement-50kg'), 100);
      expect(deviceB.stockFor('cement-50kg'), 100);

      // Device B bills a customer sale of 15 bags
      final invoiceFromB = await deviceB.finalizeInvoice(
        lines: [
          {
            'productId': 'cement-50kg',
            'name': 'Ultratech Cement 50kg',
            'quantity': 15,
            'price': 380.0,
            'unit': 'bag',
            'gst': 0,
          },
        ],
        customer: {
          'id': 'cust-ramesh',
          'name': 'Ramesh Kumar',
          'phone': '9876543210',
        },
        discount: {},
        paymentEntries: [
          {'method': 'Cash', 'amount': 5700.0},
        ],
        gstEnabled: false,
        taxInclusive: false,
        interstate: false,
      );

      expect(deviceB.stockFor('cement-50kg'), 85);
      expect(deviceB.invoices.length, 1);
      expect(deviceB.invoices.first['number'], contains(deviceB.deviceId.substring(0, 8).toUpperCase()));

      // Device B exports dirty records to cloud, Device A pulls them
      final saleRecordsFromB = deviceB.exportSyncRecords().where((r) => ['invoice', 'movement', 'payment', 'customer'].contains(r['kind'])).toList();
      await deviceA.applyRemoteRecords(saleRecordsFromB);

      // Device A now sees the exact invoice, payment, and updated stock of 85!
      expect(deviceA.invoices.length, 1);
      expect(deviceA.invoices.first['id'], invoiceFromB['id']);
      expect(deviceA.invoices.first['number'], invoiceFromB['number']);
      expect(deviceA.paidFor(invoiceFromB['id']), 5700.0);
      expect(deviceA.stockFor('cement-50kg'), 85);
    } finally {
      await deviceA.close();
      await deviceB.close();
    }
  });

  test('Simultaneous invoices on different devices never have number collisions', () async {
    final counter1 = await AppStore.openForTesting(NativeDatabase.memory());
    final counter2 = await AppStore.openForTesting(NativeDatabase.memory());

    try {
      final item = [
        {'productId': 'p1', 'name': 'Item', 'price': 50, 'quantity': 1, 'unit': 'pcs', 'gst': 0}
      ];
      final inv1 = await counter1.finalizeInvoice(
        lines: item,
        customer: {},
        discount: {},
        paymentEntries: [{'method': 'Cash', 'amount': 50}],
        gstEnabled: false,
        taxInclusive: false,
        interstate: false,
      );
      final inv2 = await counter2.finalizeInvoice(
        lines: item,
        customer: {},
        discount: {},
        paymentEntries: [{'method': 'Cash', 'amount': 50}],
        gstEnabled: false,
        taxInclusive: false,
        interstate: false,
      );

      expect(inv1['number'], isNot(equals(inv2['number'])));
      expect(inv1['number'], contains(counter1.deviceId.substring(0, 8).toUpperCase()));
      expect(inv2['number'], contains(counter2.deviceId.substring(0, 8).toUpperCase()));
    } finally {
      await counter1.close();
      await counter2.close();
    }
  });

  test('Old/existing records with dirty=0 sync to another device when markAllForSync is called', () async {
    final deviceA = await AppStore.openForTesting(NativeDatabase.memory());
    final deviceB = await AppStore.openForTesting(NativeDatabase.memory());

    try {
      // Add product on A
      await deviceA.saveProduct({
        'id': 'old-prod-1',
        'name': 'Old Drill Machine',
        'price': 1500.0,
      }, openingStock: 10);

      // Acknowledge sync so dirty becomes 0 (simulating old data created in past)
      final records = deviceA.exportSyncRecords();
      await deviceA.acknowledgeSync(records);

      // Now pending records is 0
      expect(deviceA.exportSyncRecords().length, 0);

      // Calling markAllForSync marks all existing records as dirty for full cloud sync
      await deviceA.markAllForSync();
      final markedRecords = deviceA.exportSyncRecords();
      expect(markedRecords.length, greaterThan(0));

      // Device B pulls and applies all records
      await deviceB.applyRemoteRecords(markedRecords);

      // Device B now has the old product and stock!
      expect(deviceB.products.any((p) => p['id'] == 'old-prod-1'), true);
      expect(deviceB.stockFor('old-prod-1'), 10);
    } finally {
      await deviceA.close();
      await deviceB.close();
    }
  });

  test('Local sync cursor and initialSyncDone persist cleanly without creating dirty sync records', () async {
    final store = await AppStore.openForTesting(NativeDatabase.memory());
    try {
      expect(store.isInitialSyncDone, false);
      expect(store.syncCursor, 0);
      expect(store.pendingCount, 0);

      // Save sync cursor
      await store.setSyncCursor(142);
      expect(store.syncCursor, 142);
      // Ensure cursor metadata is stored locally and NOT exported as dirty sync record
      expect(store.pendingCount, 0);
      expect(store.exportSyncRecords().any((r) => r['id'] == 'cloud-sync-cursor'), false);

      // Mark initial sync done
      await store.markInitialSyncDone();
      expect(store.isInitialSyncDone, true);
      expect(store.pendingCount, 0);
      expect(store.exportSyncRecords().any((r) => r['id'] == 'cloud-initial-sync-done'), false);

      // Reset sync cursor
      await store.resetSyncCursor();
      expect(store.syncCursor, 0);
      expect(store.isInitialSyncDone, false);
    } finally {
      await store.close();
    }
  });

  test('Multi-device payment recording updates dues and status across devices', () async {
    final counter1 = await AppStore.openForTesting(NativeDatabase.memory());
    final counter2 = await AppStore.openForTesting(NativeDatabase.memory());

    try {
      await counter1.saveProduct({'id': 'rod', 'name': 'Iron Rod', 'price': 200}, openingStock: 20);
      await counter2.applyRemoteRecords(counter1.exportSyncRecords());

      // Counter 1 creates an invoice with ₹100 partial payment (due ₹300)
      final inv = await counter1.finalizeInvoice(
        lines: [{'productId': 'rod', 'name': 'Iron Rod', 'price': 200, 'quantity': 2, 'unit': 'pcs', 'gst': 0}],
        customer: {'name': 'Suresh', 'phone': '9123456780'},
        discount: {},
        paymentEntries: [{'method': 'Cash', 'amount': 100}],
        gstEnabled: false,
        taxInclusive: false,
        interstate: false,
      );

      expect(counter1.dueFor(inv['id']), 300);

      // Counter 2 receives the invoice
      await counter2.applyRemoteRecords(counter1.exportSyncRecords());
      expect(counter2.invoices.length, 1);
      expect(counter2.dueFor(inv['id']), 300);

      // Counter 2 records remaining ₹300 payment
      await counter2.recordPayment(inv['id'], 300, 'UPI');
      expect(counter2.dueFor(inv['id']), 0);

      // Counter 1 syncs and receives the payment from Counter 2
      final paymentRecords = counter2.exportSyncRecords().where((r) => r['kind'] == 'payment').toList();
      await counter1.applyRemoteRecords(paymentRecords);

      // Counter 1 now shows invoice is fully paid (due = 0)
      expect(counter1.paidFor(inv['id']), 400);
      expect(counter1.dueFor(inv['id']), 0);
      final suresh = counter1.customerBalances.firstWhere((c) => c['name'] == 'Suresh');
      expect(suresh['due'], 0.0);
    } finally {
      await counter1.close();
      await counter2.close();
    }
  });

  test('Multi-device invoice deletion removes invoice, payments, and restores product stock on remote devices', () async {
    final counter1 = await AppStore.openForTesting(NativeDatabase.memory());
    final counter2 = await AppStore.openForTesting(NativeDatabase.memory());

    try {
      await counter1.saveProduct({'id': 'cement', 'name': 'Cement', 'price': 350}, openingStock: 50);
      await counter2.applyRemoteRecords(counter1.exportSyncRecords());

      // Counter 1 creates an invoice selling 10 bags with ₹3500 payment
      final inv = await counter1.finalizeInvoice(
        lines: [{'productId': 'cement', 'name': 'Cement', 'price': 350, 'quantity': 10, 'unit': 'bag', 'gst': 0}],
        customer: {'name': 'Ramesh', 'phone': '9876543210'},
        discount: {},
        paymentEntries: [{'method': 'Cash', 'amount': 3500}],
        gstEnabled: false,
        taxInclusive: false,
        interstate: false,
      );

      // Counter 2 syncs the sale
      await counter2.applyRemoteRecords(counter1.exportSyncRecords());
      expect(counter1.stockFor('cement'), 40);
      expect(counter2.stockFor('cement'), 40);
      expect(counter2.invoices.length, 1);

      // Acknowledge sync on counter 1 so dirty is 0
      await counter1.acknowledgeSync(counter1.exportSyncRecords());

      // Counter 1 deletes the invoice
      await counter1.deleteInvoice(inv['id']);
      expect(counter1.invoices.length, 0);
      expect(counter1.stockFor('cement'), 50);

      // Counter 1 exports the deletion tombstone records
      final deleteRecords = counter1.exportSyncRecords();
      expect(deleteRecords.any((r) => r['kind'] == 'invoice' && r['payload']['deleted'] == true), true);
      expect(deleteRecords.any((r) => r['kind'] == 'movement' && r['payload']['deleted'] == true), true);
      expect(deleteRecords.any((r) => r['kind'] == 'payment' && r['payload']['deleted'] == true), true);

      // Counter 2 receives and applies the deletion records
      await counter2.applyRemoteRecords(deleteRecords);

      // Counter 2 now has the invoice deleted, payments removed, and stock fully restored!
      expect(counter2.invoices.length, 0);
      expect(counter2.stockFor('cement'), 50);
      expect(counter2.paidFor(inv['id']), 0);
    } finally {
      await counter1.close();
      await counter2.close();
    }
  });
}

