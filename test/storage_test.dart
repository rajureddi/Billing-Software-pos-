import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:counterday/data/app_store.dart';

Future<Map<String,dynamic>> sale(AppStore s,{num paid=0,num q=2})=>s.finalizeInvoice(lines:[{'productId':'pipe','name':'Pipe','unit':'m','quantity':q,'price':100,'gst':18}],customer:{'name':'Raju','phone':'9999999999'},discount:{},paymentEntries:[{'method':'Cash','amount':paid}],gstEnabled:false,taxInclusive:false,interstate:false);
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
 late AppStore store;
 setUp(()async{store=await AppStore.openForTesting(NativeDatabase.memory());await store.saveProduct({'id':'pipe','name':'Pipe','price':100,'unit':'m'},openingStock:10);});
 tearDown(()async{await store.close();});
 test('sale commits stock and payment, payment clears dues',()async{final invoice=await sale(store,paid:50);expect(store.stockFor('pipe'),8);expect(store.dueFor(invoice['id']),150);await store.recordPayment(invoice['id'],150,'UPI');expect(store.dueFor(invoice['id']),0);await expectLater(store.recordPayment(invoice['id'],1,'Cash'),throwsArgumentError);});
 test('invalid payment makes no invoice or stock movement',()async{await expectLater(sale(store,paid:201),throwsArgumentError);expect(store.invoices,isEmpty);expect(store.stockFor('pipe'),10);});
 test('snapshot independent of later settings and product edits',()async{await store.saveSettings({'name':'Original shop'});final invoice=await sale(store);await store.saveSettings({'name':'New shop'});await store.saveProduct({'id':'pipe','name':'Renamed','price':999});expect(store.invoices.single['shop']['name'],'Original shop');expect(store.invoices.single['total'],200);invoice['shop']['name']='Mutable caller';expect(store.invoices.single['shop']['name'],'Original shop');});
 test('cancel preserves original and creates reversal once',()async{final invoice=await sale(store,paid:50);await store.cancelInvoice(invoice['id'],'Returned');expect(store.stockFor('pipe'),10);expect(store.paidFor(invoice['id']),0);expect(store.dueFor(invoice['id']),0);expect(store.invoices.single['cancelled'],true);expect(store.exportSyncRecords().where((r)=>r['kind']=='invoice').single['payload']['cancelled'],false);await expectLater(store.cancelInvoice(invoice['id'],'Again'),throwsArgumentError);});
 test('backup imported twice has no duplicates and keeps device identity',()async{await sale(store,paid:25);final backup=await store.exportBackup();final other=await AppStore.openForTesting(NativeDatabase.memory());try{final id=other.deviceId;await other.importBackup(backup);await other.importBackup(backup);expect(other.invoices.length,1);expect(other.stockFor('pipe'),8);expect(other.deviceId,id);expect(other.deviceId,isNot(store.deviceId));}finally{await other.close();}});
 test('stale sync acknowledgement leaves later edits pending',()async{final first=store.exportSyncRecords().firstWhere((r)=>r['kind']=='product');await store.saveProduct({'id':'pipe','name':'Pipe v2','price':101});await store.acknowledgeSync([{...first,'serverRevision':1}]);final pending=store.exportSyncRecords().firstWhere((r)=>r['kind']=='product');expect(pending['revision'],2);expect(pending['baseRevision'],1);});
 test('metadata conflict keeps local and supports explicit remote selection',()async{await store.applyRemoteRecords([{'id':'pipe','kind':'product','revision':2,'payload':{'id':'pipe','name':'Remote pipe','price':120}}]);expect(store.products.single['name'],'Pipe');expect(store.conflicts.length,1);await store.resolveConflict(store.conflicts.single['id'],useRemote:true);expect(store.products.single['name'],'Remote pipe');expect(store.conflicts,isEmpty);});
 test('owner binding persists and rejects different account',()async{await store.bindOwner('owner-a');await expectLater(store.bindOwner('owner-b'),throwsStateError);expect(store.boundOwner,'owner-a');});
 test('two offline sales sync without replacing stock totals',()async{await sale(store,q:8);final other=await AppStore.openForTesting(NativeDatabase.memory());try{await other.saveProduct({'id':'pipe','name':'Pipe','price':100},openingStock:0);await sale(other,q:5);final records=other.exportSyncRecords().where((r)=>['invoice','payment','movement','customer'].contains(r['kind'])).toList();await store.applyRemoteRecords(records);await store.applyRemoteRecords(records);expect(store.stockFor('pipe'),-3);expect(store.invoices.length,2);}finally{await other.close();}});
  test('customer balances accurately track invoices, payments and dues',()async{
    final invoice=await sale(store,paid:50);
    final balances=store.customerBalances;
    final raju=balances.firstWhere((c)=>c['name']=='Raju');
    expect(raju['totalInvoiced'],200.0);
    expect(raju['totalPaid'],50.0);
    expect(raju['due'],150.0);
    expect(raju['invoiceCount'],1);

    await store.recordPayment(invoice['id'],150,'UPI');
    final updated=store.customerBalances.firstWhere((c)=>c['name']=='Raju');
    expect(updated['totalPaid'],200.0);
    expect(updated['due'],0.0);
  });

  test('all movements with products enriches movements and supports negative stock',()async{
    final movementsBefore=store.allMovementsWithProducts;
    expect(movementsBefore.length,1);
    expect(movementsBefore.first['productName'],'Pipe');
    expect(movementsBefore.first['productUnit'],'m');

    // Sale of 15 when opening stock was 10 creates negative stock of -5
    await sale(store,q:15,paid:1500);
    expect(store.stockFor('pipe'),-5);
    final movementsAfter=store.allMovementsWithProducts;
    expect(movementsAfter.length,2);
    final saleMovement=movementsAfter.firstWhere((m)=>(m['quantity'] as num)<0);
    expect(saleMovement['quantity'],-15);
    expect(saleMovement['productName'],'Pipe');
  });

  test('reopen preserves invoice and sequence',()async{final dir=await Directory.systemTemp.createTemp('counterday-test-');final file=File('${dir.path}/shop.sqlite');var disk=await AppStore.openForTesting(NativeDatabase(file));try{await disk.saveProduct({'id':'pipe','name':'Pipe','price':100});final first=await sale(disk);final id=disk.deviceId;await disk.close();disk=await AppStore.openForTesting(NativeDatabase(file));expect(disk.deviceId,id);expect(disk.invoices.single['number'],first['number']);final second=await sale(disk);expect(second['number'],isNot(first['number']));}finally{await disk.close();await dir.delete(recursive:true);}});
  test('saveProduct adds custom item to catalog',()async{
    await store.saveProduct({
      'name':'Custom PVC Elbow',
      'price':45,
      'unit':'pcs',
      'category':'Plumbing',
    });
    final prod=store.products.firstWhere((p)=>p['name']=='Custom PVC Elbow');
    expect(prod['price'],45);
    expect(prod['category'],'Plumbing');
    expect(prod['unit'],'pcs');
  });

  test('case-insensitive category normalization merges cement and Cement into single category', () async {
    await store.saveProduct({
      'name': 'Birla A1 Cement',
      'price': 380,
      'unit': 'bag',
      'category': 'Cement',
    });
    await store.saveProduct({
      'name': 'UltraTech 53',
      'price': 410,
      'unit': 'bag',
      'category': 'cement',
    });
    final p1 = store.products.firstWhere((p) => p['name'] == 'Birla A1 Cement');
    final p2 = store.products.firstWhere((p) => p['name'] == 'UltraTech 53');
    expect(p1['category'], 'Cement');
    expect(p2['category'], 'Cement');
    final cementMatches = store.categories.where((c) => c.toLowerCase() == 'cement').toList();
    expect(cementMatches.length, 1);
  });

  test('deleteInvoice removes invoice, clears payments, and restores product stock', () async {
    final invoice = await sale(store, q: 4, paid: 50);
    expect(store.stockFor('pipe'), 6);
    expect(store.invoices.any((i) => i['id'] == invoice['id']), true);
    expect(store.paidFor(invoice['id']), 50);

    await store.deleteInvoice(invoice['id']);
    expect(store.invoices.any((i) => i['id'] == invoice['id']), false);
    expect(store.stockFor('pipe'), 10);
    expect(store.paidFor(invoice['id']), 0);
  });
}
