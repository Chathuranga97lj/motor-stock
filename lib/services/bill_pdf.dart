import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill.dart';
import '../utils/money.dart';

const shopName = 'OSHU Enterprises';
const shopTagline = 'Motor Bike Spare Parts & Accessories';

// Brand colours (see lib/theme.dart).
const _blue = PdfColor.fromInt(0xFF1E4FE0);
const _red = PdfColor.fromInt(0xFFE5251E);
const _navy = PdfColor.fromInt(0xFF0B1A45);
const _grey = PdfColor.fromInt(0xFF6B7280);
const _line = PdfColor.fromInt(0xFFD1D5DB);

/// A5 bill. Uses the built-in PDF font, which covers English letters only.
Future<Uint8List> buildBillPdf(Bill bill) async {
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/branding/logo_mark.png')).buffer.asUint8List(),
  );
  final doc = pw.Document(title: bill.billNo, author: shopName);
  final small = pw.TextStyle(fontSize: 8, color: _grey);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => context.pageNumber == 1
          ? _header(bill, logo, small)
          : pw.Text('${bill.billNo} (continued)', style: small),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Thank you! Ride with confidence.',
              style: pw.TextStyle(fontSize: 9, color: _navy)),
          pw.Text('Page ${context.pageNumber}/${context.pagesCount}',
              style: small),
        ],
      ),
      build: (context) => [
        if (bill.cancelled)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.all(6),
            color: const PdfColor.fromInt(0xFFFDE2E1),
            child: pw.Text(
              'CANCELLED${bill.cancelReason == null ? '' : ': ${bill.cancelReason}'}',
              style: pw.TextStyle(color: _red, fontWeight: pw.FontWeight.bold),
            ),
          ),
        _details(bill, small, bold),
        pw.SizedBox(height: 10),
        _itemsTable(bill),
        pw.SizedBox(height: 8),
        _totals(bill, bold),
        if (bill.payments.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _payments(bill, small),
        ],
      ],
    ),
  );
  return doc.save();
}

pw.Widget _header(Bill bill, pw.ImageProvider logo, pw.TextStyle small) {
  final contact = [bill.branchAddress, bill.branchPhone]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join('  |  ');
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Image(logo, width: 44, height: 44),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.RichText(
                  text: pw.TextSpan(
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        fontStyle: pw.FontStyle.italic),
                    children: [
                      const pw.TextSpan(
                          text: 'O', style: pw.TextStyle(color: _red)),
                      const pw.TextSpan(
                          text: 'SHU', style: pw.TextStyle(color: _blue)),
                      pw.TextSpan(
                          text: ' ENTERPRISES',
                          style: pw.TextStyle(
                              color: _navy,
                              fontSize: 11,
                              fontStyle: pw.FontStyle.normal)),
                    ],
                  ),
                ),
                pw.Text(shopTagline, style: small),
                pw.Text('${bill.branchName} branch',
                    style: pw.TextStyle(fontSize: 9, color: _navy)),
                if (contact.isNotEmpty) pw.Text(contact, style: small),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('BILL',
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy)),
              pw.Text(bill.billNo,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(height: 2, color: _red),
      pw.SizedBox(height: 8),
    ],
  );
}

pw.Widget _details(Bill bill, pw.TextStyle small, pw.TextStyle bold) {
  pw.Widget pair(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(children: [
          pw.SizedBox(width: 58, child: pw.Text(label, style: small)),
          pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 9))),
        ]),
      );
  final customer = [bill.customerName, bill.customerPhone]
      .whereType<String>()
      .join('  |  ');
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(children: [
          pair('Date', formatDateTime(bill.createdAt)),
          pair('Payment', bill.cancelled ? '-' : bill.paymentStatus.label),
        ]),
      ),
      pw.SizedBox(width: 12),
      pw.Expanded(
        child: pw.Column(children: [
          pair('Customer', customer.isEmpty ? '-' : customer),
          pair('Issued by', bill.issuedBy ?? '-'),
        ]),
      ),
    ],
  );
}

pw.Widget _itemsTable(Bill bill) {
  const head = pw.TextStyle(fontSize: 8, color: PdfColors.white);
  const cell = pw.TextStyle(fontSize: 9);
  return pw.TableHelper.fromTextArray(
    headers: ['#', 'Item', 'Qty', 'Price', 'Amount'],
    data: [
      for (final (i, item) in bill.items.indexed)
        [
          '${i + 1}',
          item.partNo == null ? item.partName : '${item.partName}\n${item.partNo}',
          '${item.quantity}',
          formatMoney(item.unitPrice, symbol: false),
          formatMoney(item.lineTotal, symbol: false),
        ],
    ],
    headerStyle: head.copyWith(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: _navy),
    cellStyle: cell,
    border: null,
    rowDecoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)),
    ),
    columnWidths: {
      0: const pw.FixedColumnWidth(16),
      1: const pw.FlexColumnWidth(),
      2: const pw.FixedColumnWidth(28),
      3: const pw.FixedColumnWidth(58),
      4: const pw.FixedColumnWidth(64),
    },
    cellAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerLeft,
      2: pw.Alignment.center,
      3: pw.Alignment.centerRight,
      4: pw.Alignment.centerRight,
    },
    headerAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerLeft,
      2: pw.Alignment.center,
      3: pw.Alignment.centerRight,
      4: pw.Alignment.centerRight,
    },
  );
}

pw.Widget _totals(Bill bill, pw.TextStyle bold) {
  pw.Widget row(String label, String value, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          children: [
            pw.Expanded(
                child: pw.Text(label,
                    style: strong ? bold : const pw.TextStyle(fontSize: 9))),
            pw.Text(value,
                style: strong
                    ? pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)
                    : const pw.TextStyle(fontSize: 9)),
          ],
        ),
      );
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 170,
      child: pw.Column(children: [
        row('Items', '${bill.itemCount}'),
        row('Subtotal', formatMoney(bill.subtotal)),
        if (bill.discount > 0) row('Discount', '- ${formatMoney(bill.discount)}'),
        pw.Divider(color: _navy, thickness: 1),
        row('TOTAL', formatMoney(bill.total), strong: true),
        if (!bill.cancelled) ...[
          row('Paid', formatMoney(bill.amountPaid)),
          if (bill.hasBalance)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 4),
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: const PdfColor.fromInt(0xFFFDE2E1),
              child: pw.Row(children: [
                pw.Expanded(
                    child: pw.Text('BALANCE DUE',
                        style: pw.TextStyle(
                            color: _red,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold))),
                pw.Text(formatMoney(bill.balance),
                    style: pw.TextStyle(
                        color: _red,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
              ]),
            ),
        ],
      ]),
    ),
  );
}

pw.Widget _payments(Bill bill, pw.TextStyle small) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Payments received',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      for (final p in bill.payments)
        pw.Row(children: [
          pw.SizedBox(width: 90, child: pw.Text(formatDateTime(p.createdAt), style: small)),
          pw.SizedBox(width: 70, child: pw.Text(p.method.label, style: small)),
          pw.Expanded(child: pw.Text(p.note ?? '', style: small)),
          pw.Text(formatMoney(p.amount), style: const pw.TextStyle(fontSize: 8)),
        ]),
    ],
  );
}

/// Opens Android's share sheet (WhatsApp, email, ...) with the bill PDF.
Future<void> shareBill(Bill bill) async {
  final bytes = await buildBillPdf(bill);
  await Printing.sharePdf(bytes: bytes, filename: '${bill.billNo}.pdf');
}

/// Opens the system print dialog.
Future<void> printBill(Bill bill) => Printing.layoutPdf(
      name: bill.billNo,
      format: PdfPageFormat.a5,
      onLayout: (_) => buildBillPdf(bill),
    );
