// Money is calculated in integer paise; quantities allow three decimal places.
int paise(num value) {
  if (!value.isFinite) throw ArgumentError('Enter a valid amount.');
  return (value * 100).round();
}

int _round(int numerator, int denominator) =>
    (numerator + denominator ~/ 2) ~/ denominator;
int _discount(int base, Map discount) {
  final value = (discount['value'] as num?) ?? 0;
  if (!value.isFinite || value < 0) {
    throw ArgumentError('Discount cannot be negative.');
  }
  final result = discount['type'] == 'percent'
      ? _round(base * paise(value), 10000)
      : paise(value);
  if (result > base || (discount['type'] == 'percent' && value > 100)) {
    throw ArgumentError('Discount exceeds the amount.');
  }
  return result;
}

Map<String, dynamic> calculateBill({
  required List<Map<String, dynamic>> lines,
  Map<String, dynamic> discount = const {},
  bool gstEnabled = false,
  bool taxInclusive = false,
  bool interstate = false,
}) {
  final bases = <int>[];
  final itemDiscounts = <int>[];
  var subtotal = 0;
  for (final line in lines) {
    final quantity = (line['quantity'] as num?) ?? 0;
    final price = (line['price'] as num?) ?? -1;
    final rate = (line['gst'] as num?) ?? 0;
    if (!quantity.isFinite ||
        quantity <= 0 ||
        ((quantity * 1000).round() - quantity * 1000).abs() > 0.00001) {
      throw ArgumentError(
        'Quantity must be positive with at most three decimal places.',
      );
    }
    if (!price.isFinite ||
        price < 0 ||
        !rate.isFinite ||
        rate < 0 ||
        rate > 100) {
      throw ArgumentError('Invalid price or tax rate.');
    }
    if ((line['name'] ?? '').toString().trim().isEmpty) {
      throw ArgumentError('Item name is required.');
    }
    final gross = _round(paise(price) * (quantity * 1000).round(), 1000);
    final reduction = _discount(gross, (line['discount'] as Map?) ?? {});
    subtotal += gross;
    itemDiscounts.add(reduction);
    bases.add(gross - reduction);
  }
  final baseTotal = bases.fold(0, (a, b) => a + b);
  final overall = _discount(baseTotal, discount);
  final allocations = bases
      .map((base) => baseTotal == 0 ? 0 : overall * base ~/ baseTotal)
      .toList();
  var remainder = overall - allocations.fold(0, (a, b) => a + b);
  final order = List.generate(bases.length, (i) => i)
    ..sort(
      (a, b) => baseTotal == 0
          ? a.compareTo(b)
          : (overall * bases[b] % baseTotal).compareTo(
              overall * bases[a] % baseTotal,
            ),
    );
  for (final index in order) {
    if (remainder <= 0) break;
    allocations[index]++;
    remainder--;
  }
  var taxTotal = 0;
  var taxableTotal = 0;
  final calculated = <Map<String, dynamic>>[];
  for (var i = 0; i < lines.length; i++) {
    final net = bases[i] - allocations[i];
    final rate = gstEnabled ? paise((lines[i]['gst'] as num?) ?? 0) : 0;
    final taxable = taxInclusive && rate > 0
        ? _round(net * 10000, 10000 + rate)
        : net;
    final tax = taxInclusive ? net - taxable : _round(taxable * rate, 10000);
    taxTotal += tax;
    taxableTotal += taxable;

    // Line level values based on item price & single item discount only (not reduced by overall discount)
    final itemBase = bases[i];
    final lineTaxable = taxInclusive && rate > 0
        ? _round(itemBase * 10000, 10000 + rate)
        : itemBase;
    final lineTax = taxInclusive
        ? itemBase - lineTaxable
        : _round(lineTaxable * rate, 10000);
    final lineTotal = taxInclusive ? itemBase : (lineTaxable + lineTax);

    calculated.add({
      ...lines[i],
      'itemDiscount': itemDiscounts[i] / 100,
      'overallDiscount': allocations[i] / 100,
      'discountAmount': itemDiscounts[i] / 100,
      'taxable': lineTaxable / 100,
      'tax': lineTax / 100,
      'total': lineTotal / 100,
      'netTaxable': taxable / 100,
      'netTax': tax / 100,
      'netTotal': (taxable + tax) / 100,
      'cgst': interstate ? 0 : (tax ~/ 2) / 100,
      'sgst': interstate ? 0 : (tax - tax ~/ 2) / 100,
      'igst': interstate ? tax / 100 : 0,
    });
  }
  return {
    'lines': calculated,
    'subtotal': subtotal / 100,
    'itemDiscountTotal': itemDiscounts.fold(0, (a, b) => a + b) / 100,
    'overallDiscountTotal': overall / 100,
    'discountTotal': (itemDiscounts.fold(0, (a, b) => a + b) + overall) / 100,
    'taxableTotal': taxableTotal / 100,
    'taxTotal': taxTotal / 100,
    'total': (taxableTotal + taxTotal) / 100,
  };
}
