import 'package:flutter_test/flutter_test.dart';
import 'package:counterday/domain/billing.dart';

Map<String,dynamic> item({num price=100,num quantity=1,num gst=18,Map<String,dynamic> discount=const {}})=>{'name':'Pipe','price':price,'quantity':quantity,'gst':gst,'discount':discount,'unit':'m'};
void main(){
 test('fractional quantity and item then overall discount before GST',(){final bill=calculateBill(lines:[item(price:100,quantity:2.5,discount:{'type':'percent','value':10})],discount:{'type':'amount','value':25},gstEnabled:true);expect(bill['subtotal'],250);expect(bill['discountTotal'],50);expect(bill['taxableTotal'],200);expect(bill['taxTotal'],36);expect(bill['total'],236);});
 test('inclusive tax extracts rather than adding GST',(){final bill=calculateBill(lines:[item(price:118)],gstEnabled:true,taxInclusive:true);expect(bill['taxableTotal'],100);expect(bill['taxTotal'],18);expect(bill['total'],118);});
 test('non GST ignores catalog GST rate',(){final bill=calculateBill(lines:[item(price:118)],gstEnabled:false,taxInclusive:true);expect(bill['total'],118);expect(bill['taxTotal'],0);});
 test('proportional discount remainder preserves all paise',(){final bill=calculateBill(lines:List.generate(3,(_)=>item(price:1,gst:0)),discount:{'type':'amount','value':1});expect(bill['total'],2);expect(bill['discountTotal'],1);expect((bill['lines'] as List).fold<int>(0,(s,l)=>s+paise(l['overallDiscount'])),100);});
 test('CGST plus SGST equals tax; interstate uses IGST',(){final local=calculateBill(lines:[item(price:1.01)],gstEnabled:true);final l=(local['lines'] as List).single;expect(paise(l['cgst'])+paise(l['sgst']),paise(l['tax']));final remote=calculateBill(lines:[item()],gstEnabled:true,interstate:true);expect(remote['lines'][0]['igst'],18);expect(remote['lines'][0]['cgst'],0);});
 test('reject invalid numbers, quantities and excessive discounts',(){for(final q in [0,-1,1.0001,double.nan]){expect(()=>calculateBill(lines:[item(quantity:q)]),throwsArgumentError);}expect(()=>calculateBill(lines:[item(discount:{'type':'percent','value':101})]),throwsArgumentError);expect(()=>calculateBill(lines:[item()],discount:{'value':101}),throwsArgumentError);});
 test('mixed rates allocate overall discount fairly',(){final b=calculateBill(lines:[item(price:100,gst:5),item(price:100,gst:18)],discount:{'type':'percent','value':10},gstEnabled:true);expect(b['total'],200.7);expect(b['taxTotal'],20.7);});
 test('item discount is on product row while overall discount applies only at gross payment level',(){
  final bill = calculateBill(
    lines: [
      item(price: 100, quantity: 2, discount: {'type': 'percent', 'value': 10}),
      item(price: 50, quantity: 2),
    ],
    discount: {'type': 'amount', 'value': 30},
    gstEnabled: false,
  );
  final l1 = bill['lines'][0];
  final l2 = bill['lines'][1];
  expect(l1['discountAmount'], 20);
  expect(l1['total'], 180);
  expect(l2['discountAmount'], 0);
  expect(l2['total'], 100);
  expect(bill['subtotal'], 300);
  expect(bill['itemDiscountTotal'], 20);
  expect(bill['overallDiscountTotal'], 30);
  expect(bill['discountTotal'], 50);
  expect(bill['total'], 250);
 });
}
