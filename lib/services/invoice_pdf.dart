import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Generates and prints world-class, professional GST and retail invoices.
class InvoicePdf {
  static double _n(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static String _money(dynamic v) => '₹${_n(v).toStringAsFixed(2)}';
  static String _s(dynamic v) => v?.toString() ?? '';

  static String _numberToWords(num amount) {
    final n = amount.floor();
    if (n <= 0) return 'Rupees Zero Only';
    final ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    final tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
    String helper(int num) {
      if (num == 0) return '';
      if (num < 20) return '${ones[num]} ';
      if (num < 100) return '${tens[num ~/ 10]} ${helper(num % 10)}';
      return '${ones[num ~/ 100]} Hundred ${helper(num % 100)}';
    }

    var temp = n;
    var str = '';
    if (temp >= 10000000) {
      str += '${helper(temp ~/ 10000000)}Crore ';
      temp %= 10000000;
    }
    if (temp >= 100000) {
      str += '${helper(temp ~/ 100000)}Lakh ';
      temp %= 100000;
    }
    if (temp >= 1000) {
      str += '${helper(temp ~/ 1000)}Thousand ';
      temp %= 1000;
    }
    if (temp > 0) {
      str += helper(temp);
    }
    final paiseVal = ((amount - n) * 100).round();
    final paiseStr = paiseVal > 0 ? 'and $paiseVal Paise ' : '';
    return 'Rupees ${str.trim()} ${paiseStr}Only';
  }

  static Future<Uint8List> generate(
    Map<String, dynamic> invoice, {
    String paper = 'A4',
  }) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );

    final shop = Map<String, dynamic>.from(invoice['shop'] as Map? ?? {});
    final customer = Map<String, dynamic>.from(
      invoice['customer'] as Map? ?? {},
    );
    final lines = (invoice['lines'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final thermal = paper == '58mm' || paper == '80mm';
    final format = switch (paper) {
      'A5' => PdfPageFormat.a5,
      '58mm' => PdfPageFormat(
        58 * PdfPageFormat.mm,
        297 * PdfPageFormat.mm,
        marginAll: 3 * PdfPageFormat.mm,
      ),
      '80mm' => PdfPageFormat(
        80 * PdfPageFormat.mm,
        297 * PdfPageFormat.mm,
        marginAll: 4 * PdfPageFormat.mm,
      ),
      _ => PdfPageFormat.a4,
    };

    final tax = _n(invoice['taxTotal']);
    final total = _n(invoice['total']);
    final paid = _n(invoice['paid']);
    final balance = invoice.containsKey('balance')
        ? _n(invoice['balance'])
        : (total - paid);
    final isGst = invoice['gstEnabled'] == true;
    final isCancelled = invoice['cancelled'] == true;
    final date = DateTime.tryParse(_s(invoice['createdAt']));

    // Colors
    final primary = PdfColor.fromHex('#1E293B');
    final accent = PdfColor.fromHex('#E66C3B');
    final green = PdfColor.fromHex('#2E7D32');
    final red = PdfColor.fromHex('#C62828');
    final border = PdfColor.fromHex('#CBD5E1');
    final bgLight = PdfColor.fromHex('#F8FAFC');
    final textMuted = PdfColor.fromHex('#64748B');

    pw.Image? logo;
    try {
      final data = _s(shop['logoBase64']);
      if (data.isNotEmpty) {
        logo = pw.Image(
          pw.MemoryImage(
            base64Decode(data.contains(',') ? data.split(',').last : data),
          ),
          height: thermal ? 28 : 42,
        );
      }
    } catch (_) {}

    // MultiPage document
    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: thermal
            ? const pw.EdgeInsets.all(6)
            : (paper == 'A5'
                ? const pw.EdgeInsets.all(16)
                : const pw.EdgeInsets.all(26)),
        maxPages: 1000,
        theme: pw.ThemeData.withFont(base: font, bold: font).copyWith(
          defaultTextStyle: pw.TextStyle(
            font: font,
            fontSize: thermal ? 8 : (paper == 'A5' ? 8.5 : 9.5),
            color: primary,
          ),
        ),
        footer: (context) => thermal
            ? pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    '${_s(invoice['number'])} · Page ${context.pageNumber}/${context.pagesCount}',
                    style: pw.TextStyle(fontSize: 7, color: textMuted),
                  ),
                ),
              )
            : pw.Container(
                padding: const pw.EdgeInsets.only(top: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: border, width: 0.5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Generated on ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 7.5, color: textMuted),
                    ),
                    pw.Text(
                      'Invoice ${_s(invoice['number'])}  •  Page ${context.pageNumber} of ${context.pagesCount}',
                      style: pw.TextStyle(fontSize: 7.5, color: textMuted),
                    ),
                  ],
                ),
              ),
        build: (_) => thermal
            ? _buildThermalBill(
                invoice: invoice,
                shop: shop,
                customer: customer,
                lines: lines,
                logo: logo,
                date: date,
                total: total,
                paid: paid,
                balance: balance,
                tax: tax,
                isGst: isGst,
                isCancelled: isCancelled,
                primary: primary,
                textMuted: textMuted,
                border: border,
              )
            : _buildStandardInvoice(
                invoice: invoice,
                shop: shop,
                customer: customer,
                lines: lines,
                logo: logo,
                date: date,
                total: total,
                paid: paid,
                balance: balance,
                tax: tax,
                isGst: isGst,
                isCancelled: isCancelled,
                paper: paper,
                primary: primary,
                accent: accent,
                green: green,
                red: red,
                border: border,
                bgLight: bgLight,
                textMuted: textMuted,
              ),
      ),
    );

    return doc.save();
  }

  // --- STANDARD A4 / A5 INVOICE ---
  static List<pw.Widget> _buildStandardInvoice({
    required Map<String, dynamic> invoice,
    required Map<String, dynamic> shop,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> lines,
    required pw.Image? logo,
    required DateTime? date,
    required double total,
    required double paid,
    required double balance,
    required double tax,
    required bool isGst,
    required bool isCancelled,
    required String paper,
    required PdfColor primary,
    required PdfColor accent,
    required PdfColor green,
    required PdfColor red,
    required PdfColor border,
    required PdfColor bgLight,
    required PdfColor textMuted,
  }) {
    final itemDiscTotal = _n(invoice['itemDiscountTotal']);
    final billDiscTotal = _n(invoice['overallDiscountTotal']);
    final totalDisc = _n(invoice['discountTotal']);
    final hasItemDisc = itemDiscTotal > 0 || lines.any((l) => _n(l['itemDiscount']) > 0 || _n(l['discountAmount']) > 0);
    final hasOverallDisc = billDiscTotal > 0;
    final isPaid = balance <= 0.009;
    final isPartial = paid > 0.009 && balance > 0.009;

    return [
      // TOP HEADER & BRANDING
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            logo,
            pw.SizedBox(width: 14),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _s(shop['name']).isEmpty ? 'Your Shop' : _s(shop['name']),
                  style: pw.TextStyle(
                    fontSize: paper == 'A5' ? 16 : 21,
                    fontWeight: pw.FontWeight.bold,
                    color: primary,
                  ),
                ),
                if (_s(shop['tagline']).isNotEmpty)
                  pw.Text(
                    _s(shop['tagline']),
                    style: pw.TextStyle(fontSize: 8.5, color: textMuted),
                  ),
                if (_s(shop['address']).isNotEmpty)
                  pw.Text(_s(shop['address']), style: const pw.TextStyle(fontSize: 8.5)),
                pw.Row(
                  children: [
                    if (_s(shop['phone']).isNotEmpty)
                      pw.Text('Ph: ${_s(shop['phone'])}  ', style: const pw.TextStyle(fontSize: 8.5)),
                    if (_s(shop['email']).isNotEmpty)
                      pw.Text('Email: ${_s(shop['email'])}', style: const pw.TextStyle(fontSize: 8.5)),
                  ],
                ),
                if (_s(shop['gstin']).isNotEmpty)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 4),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: bgLight,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                      border: pw.Border.all(color: border, width: 0.5),
                    ),
                    child: pw.Text(
                      'GSTIN: ${_s(shop['gstin'])}',
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          // INVOICE META CARD
          pw.Container(
            width: paper == 'A5' ? 155 : 185,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: bgLight,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              border: pw.Border.all(color: border, width: 0.7),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: isCancelled ? red : (isGst ? primary : accent),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      isCancelled
                          ? 'CANCELLED INVOICE'
                          : (isGst ? 'TAX INVOICE' : 'RETAIL INVOICE'),
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                _metaRow('Invoice No:', _s(invoice['number']), isBold: true),
                _metaRow(
                  'Date:',
                  date == null
                      ? _s(invoice['createdAt'])
                      : DateFormat('dd MMM yyyy, hh:mm a').format(date.toLocal()),
                ),
                if (_s(customer['state']).isNotEmpty || _s(shop['state']).isNotEmpty)
                  _metaRow('Place of Supply:', _s(customer['state']).isNotEmpty ? _s(customer['state']) : _s(shop['state'])),
                pw.SizedBox(height: 4),
                // Payment Status Badge
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  decoration: pw.BoxDecoration(
                    color: isCancelled
                        ? PdfColors.grey200
                        : (isPaid
                            ? PdfColor.fromHex('#E8F5E9')
                            : (isPartial
                                ? PdfColor.fromHex('#FFF3E0')
                                : PdfColor.fromHex('#FFEBEE'))),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      isCancelled
                          ? 'STATUS: CANCELLED'
                          : (isPaid
                              ? 'STATUS: PAID IN FULL'
                              : (isPartial
                                  ? 'PARTIALLY PAID (DUE: ${_money(balance)})'
                                  : 'STATUS: UNPAID / DUE')),
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: isCancelled
                            ? PdfColors.grey700
                            : (isPaid ? green : (isPartial ? accent : red)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      pw.SizedBox(height: 12),

      // PARTIES: BILLED BY & BILLED TO
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: border, width: 0.7),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Billed To (Customer)
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(7),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'BILLED TO (BUYER):',
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: textMuted),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      _s(customer['name']).isEmpty ? 'Walk-in Customer' : _s(customer['name']),
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                    if (_s(customer['phone']).isNotEmpty)
                      pw.Text('Phone: ${_s(customer['phone'])}', style: const pw.TextStyle(fontSize: 8)),
                    if (_s(customer['address']).isNotEmpty)
                      pw.Text('Address: ${_s(customer['address'])}', style: const pw.TextStyle(fontSize: 8)),
                    if (_s(customer['gstin']).isNotEmpty)
                      pw.Text('Customer GSTIN: ${_s(customer['gstin'])}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
            pw.Container(width: 0.7, height: 50, color: border),
            // Shipping / Counter Note
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(7),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'SALE DETAILS:',
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: textMuted),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Mode: Retail Counter Sale',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                    if (isGst)
                      pw.Text(
                        invoice['taxInclusive'] == true
                            ? 'Tax Treatment: Tax Inclusive'
                            : 'Tax Treatment: Tax Added',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    if (invoice['interstate'] == true)
                      pw.Text('IGST Applicable (Interstate Sale)', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      pw.SizedBox(height: 10),

      // ITEMS TABLE
      pw.Table(
        border: pw.TableBorder.all(color: border, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(20), // S.No
          1: const pw.FlexColumnWidth(4.0), // Description & HSN
          2: const pw.FixedColumnWidth(44), // Qty & Unit
          3: const pw.FixedColumnWidth(48), // Rate
          4: const pw.FixedColumnWidth(46), // Discount
          5: const pw.FixedColumnWidth(50), // Taxable
          if (isGst) 6: const pw.FixedColumnWidth(44), // GST %
          7: const pw.FixedColumnWidth(54), // Total
        },
        children: [
          // Header
          pw.TableRow(
            decoration: pw.BoxDecoration(color: primary),
            children: [
              _tableHeaderCell('#', align: pw.TextAlign.center),
              _tableHeaderCell('Item Description'),
              _tableHeaderCell('Qty', align: pw.TextAlign.right),
              _tableHeaderCell('Rate (₹)', align: pw.TextAlign.right),
              _tableHeaderCell('Disc (₹)', align: pw.TextAlign.right),
              _tableHeaderCell('Taxable', align: pw.TextAlign.right),
              if (isGst) _tableHeaderCell('GST', align: pw.TextAlign.right),
              _tableHeaderCell('Total (₹)', align: pw.TextAlign.right),
            ],
          ),
          // Line items
          for (var i = 0; i < lines.length; i++)
            _buildTableRow(
              index: i + 1,
              line: lines[i],
              isGst: isGst,
              isEven: i % 2 == 1,
              bgLight: bgLight,
              textMuted: textMuted,
            ),
        ],
      ),

      pw.SizedBox(height: 10),

      // BOTTOM SUMMARY: LEFT (PAYMENTS/BANK/NOTES) & RIGHT (FINANCIAL TOTALS)
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Left: Payment entries, Bank/UPI, Terms
          pw.Expanded(
            flex: 5,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Payment breakdown
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: bgLight,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: border, width: 0.5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PAYMENT INFORMATION:',
                        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: textMuted),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Amount Received:', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text(_money(paid), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: green)),
                        ],
                      ),
                      if (balance > 0.009)
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Outstanding Balance Due:', style: pw.TextStyle(fontSize: 8, color: red)),
                            pw.Text(_money(balance), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: red)),
                          ],
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),
                // Bank & UPI
                if (_s(shop['bank']).isNotEmpty || _s(shop['upi']).isNotEmpty) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      border: pw.Border.all(color: border, width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('BANK / UPI DETAILS:', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: textMuted)),
                        if (_s(shop['bank']).isNotEmpty)
                          pw.Text('Bank: ${_s(shop['bank'])}', style: const pw.TextStyle(fontSize: 7.5)),
                        if (_s(shop['upi']).isNotEmpty)
                          pw.Text('UPI ID: ${_s(shop['upi'])}', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                // Terms
                pw.Text(
                  'Terms & Conditions: ${_s(shop['footer']).isEmpty ? '1. Goods once sold are covered by standard store policy. 2. Subject to local jurisdiction.' : _s(shop['footer'])}',
                  style: pw.TextStyle(fontSize: 7, color: textMuted),
                ),
              ],
            ),
          ),

          pw.SizedBox(width: 14),

          // Right: Detailed Totals Box
          pw.Expanded(
            flex: 5,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: border, width: 0.7),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                children: [
                  _summaryRow('Gross Subtotal', invoice['subtotal']),
                  if (hasItemDisc)
                    _summaryRow(
                      'Item Level Discounts',
                      -itemDiscTotal,
                      textColor: accent,
                    ),
                  if (hasOverallDisc)
                    _summaryRow(
                      'Overall Bill Discount',
                      -billDiscTotal,
                      textColor: accent,
                    ),
                  if (totalDisc > 0 && !hasItemDisc && !hasOverallDisc)
                    _summaryRow('Discounts', -totalDisc, textColor: accent),
                  _summaryRow('Net Taxable Value', invoice['taxableTotal'] ?? (total - tax)),
                  if (isGst) ...[
                    if (invoice['interstate'] == true)
                      _summaryRow('IGST', tax)
                    else ...[
                      _summaryRow('CGST', (tax * 50).round() / 100),
                      _summaryRow('SGST', tax - (tax * 50).round() / 100),
                    ],
                  ],
                  // Grand Total
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: primary,
                      borderRadius: const pw.BorderRadius.only(
                        bottomLeft: pw.Radius.circular(3),
                        bottomRight: pw.Radius.circular(3),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'GRAND TOTAL:',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.Text(
                          _money(total),
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      pw.SizedBox(height: 8),

      // AMOUNT IN WORDS & SIGNATURE
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Amount in Words: ${_numberToWords(total)}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
                if (totalDisc > 0)
                  pw.Text(
                    'Total Discount Benefited: ${_money(totalDisc)}',
                    style: pw.TextStyle(fontSize: 7.5, color: green, fontWeight: pw.FontWeight.bold),
                  ),
              ],
            ),
          ),
          pw.Container(
            width: 140,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(height: 18),
                pw.Container(width: 120, height: 0.5, color: border),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Authorized Signatory',
                  style: pw.TextStyle(fontSize: 7.5, color: textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  // --- THERMAL 58mm / 80mm RECEIPT ---
  static List<pw.Widget> _buildThermalBill({
    required Map<String, dynamic> invoice,
    required Map<String, dynamic> shop,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> lines,
    required pw.Image? logo,
    required DateTime? date,
    required double total,
    required double paid,
    required double balance,
    required double tax,
    required bool isGst,
    required bool isCancelled,
    required PdfColor primary,
    required PdfColor textMuted,
    required PdfColor border,
  }) {
    final itemDiscTotal = _n(invoice['itemDiscountTotal']);
    final billDiscTotal = _n(invoice['overallDiscountTotal']);
    final totalDisc = _n(invoice['discountTotal']);

    return [
      if (logo != null) pw.Center(child: logo),
      pw.Center(
        child: pw.Text(
          _s(shop['name']).isEmpty ? 'Your Shop' : _s(shop['name']),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      ),
      if (_s(shop['tagline']).isNotEmpty)
        pw.Center(
          child: pw.Text(_s(shop['tagline']), style: const pw.TextStyle(fontSize: 7)),
        ),
      if (_s(shop['address']).isNotEmpty)
        pw.Center(
          child: pw.Text(_s(shop['address']), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
        ),
      if (_s(shop['phone']).isNotEmpty)
        pw.Center(child: pw.Text('Tel: ${_s(shop['phone'])}', style: const pw.TextStyle(fontSize: 7))),
      if (_s(shop['gstin']).isNotEmpty)
        pw.Center(
          child: pw.Text('GSTIN: ${_s(shop['gstin'])}', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
        ),
      pw.Center(
        child: pw.Text(
          isCancelled ? '*** CANCELLED BILL ***' : (isGst ? 'TAX INVOICE' : 'RETAIL RECEIPT'),
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
      ),
      _dottedLine(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Inv: ${_s(invoice['number'])}', style: const pw.TextStyle(fontSize: 7)),
          pw.Text(
            date == null ? '' : DateFormat('dd/MM/yy hh:mm a').format(date.toLocal()),
            style: const pw.TextStyle(fontSize: 7),
          ),
        ],
      ),
      if (_s(customer['name']).isNotEmpty && _s(customer['name']) != 'Walk-in customer')
        pw.Text('Customer: ${_s(customer['name'])}', style: const pw.TextStyle(fontSize: 7)),
      _dottedLine(),
      // Lines Header
      pw.Row(
        children: [
          pw.Expanded(flex: 5, child: pw.Text('Item', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
          pw.Expanded(flex: 2, child: pw.Text('Qty', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
          pw.Expanded(flex: 3, child: pw.Text('Price', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
          pw.Expanded(flex: 3, child: pw.Text('Total', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
        ],
      ),
      _dottedLine(),
      // Lines
      for (final l in lines) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_s(l['name']), style: const pw.TextStyle(fontSize: 7.5)),
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text(
                      _n(l['itemDiscount'] ?? l['discountAmount']) > 0
                          ? 'Disc: -${_money(l['itemDiscount'] ?? l['discountAmount'])}'
                          : (_s(l['hsn']).isNotEmpty ? 'HSN: ${l['hsn']}' : ''),
                      style: const pw.TextStyle(fontSize: 6.5),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('${_n(l['quantity'])}', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(_money(l['price']), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(_money(l['total']), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      _dottedLine(),
      // Totals
      _thermalRow('Subtotal:', _money(invoice['subtotal'])),
      if (itemDiscTotal > 0)
        _thermalRow('Item Discounts:', '-${_money(itemDiscTotal)}'),
      if (billDiscTotal > 0)
        _thermalRow('Bill Discount:', '-${_money(billDiscTotal)}'),
      if (totalDisc > 0 && itemDiscTotal == 0 && billDiscTotal == 0)
        _thermalRow('Discount:', '-${_money(totalDisc)}'),
      if (isGst) ...[
        _thermalRow('Taxable:', _money(invoice['taxableTotal'] ?? (total - tax))),
        _thermalRow('GST:', _money(tax)),
      ],
      _dottedLine(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('TOTAL:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(_money(total), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
      if (paid > 0) _thermalRow('Paid:', _money(paid)),
      if (balance > 0.009)
        _thermalRow('Balance Due:', _money(balance), isBold: true),
      _dottedLine(),
      if (_s(shop['upi']).isNotEmpty)
        pw.Center(child: pw.Text('UPI ID: ${_s(shop['upi'])}', style: const pw.TextStyle(fontSize: 7))),
      pw.Center(
        child: pw.Text(
          _s(shop['footer']).isEmpty ? 'Thank you! Visit again.' : _s(shop['footer']),
          style: const pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ];
  }

  // Helper widgets
  static pw.Widget _metaRow(String label, String value, {bool isBold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 7.5)),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 7.5, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
            ),
          ],
        ),
      );

  static pw.Widget _summaryRow(String label, dynamic value, {PdfColor? textColor}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: textColor)),
            pw.Text(
              _money(value),
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: textColor),
            ),
          ],
        ),
      );

  static pw.Widget _tableHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          textAlign: align,
        ),
      );

  static pw.TableRow _buildTableRow({
    required int index,
    required Map<String, dynamic> line,
    required bool isGst,
    required bool isEven,
    required PdfColor bgLight,
    required PdfColor textMuted,
  }) {
    final totalLineDisc = _n(line['itemDiscount'] ?? line['discountAmount']);

    String discLabel = '-';
    if (totalLineDisc > 0) {
      discLabel = _money(totalLineDisc);
      final discMap = line['discount'] as Map?;
      if (discMap != null && discMap['type'] == 'percent') {
        discLabel = '${discMap['value']}% (${_money(totalLineDisc)})';
      }
    }

    return pw.TableRow(
      decoration: isEven ? pw.BoxDecoration(color: bgLight) : const pw.BoxDecoration(),
      children: [
        // S.No
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: pw.Text('$index', style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center),
        ),
        // Item Description & HSN
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_s(line['name']), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              if (_s(line['hsn']).isNotEmpty)
                pw.Text('HSN: ${_s(line['hsn'])}', style: pw.TextStyle(fontSize: 6.5, color: textMuted)),
            ],
          ),
        ),
        // Qty & Unit
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text('${_n(line['quantity'])} ${_s(line['unit'])}', style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.right),
        ),
        // Unit Price
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(_money(line['price']), style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.right),
        ),
        // Discount
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(discLabel, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right),
        ),
        // Taxable
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(_money(line['taxable']), style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.right),
        ),
        // GST %
        if (isGst)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: pw.Text('${_n(line['gst'])}%\n${_money(line['tax'])}', style: const pw.TextStyle(fontSize: 6.5), textAlign: pw.TextAlign.right),
          ),
        // Total
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(_money(line['total']), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
        ),
      ],
    );
  }

  static pw.Widget _dottedLine() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text(
          '- - - - - - - - - - - - - - - - - - - - - - - - - - - -',
          style: const pw.TextStyle(fontSize: 6),
          maxLines: 1,
        ),
      );

  static pw.Widget _thermalRow(String label, String value, {bool isBold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(value, style: pw.TextStyle(fontSize: 7, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  static Future<void> printInvoice(Map invoice, {String paper = 'A4'}) async {
    final snapshot = Map<String, dynamic>.from(invoice);
    final bytes = await generate(snapshot, paper: paper);
    await Printing.layoutPdf(
      name: 'Invoice ${snapshot['number']}',
      onLayout: (_) async => bytes,
    );
  }

  static Future<void> shareInvoice(Map invoice, {String paper = 'A4'}) async {
    final snapshot = Map<String, dynamic>.from(invoice);
    final filename = 'Invoice-${snapshot['number'] ?? snapshot['id']}'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    await Printing.sharePdf(
      bytes: await generate(snapshot, paper: paper),
      filename: '$filename.pdf',
    );
  }
}
