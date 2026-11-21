import 'package:flutter/services.dart';

const currencySymbol = 'Rs.';

/// 1234567.5 -> "Rs. 1,234,567.50"
String formatMoney(num amount, {bool symbol = true}) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot);
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  final text = '${negative ? '-' : ''}$grouped${fixed.substring(dot)}';
  return symbol ? '$currencySymbol $text' : text;
}

/// Money typed into a field: digits with up to 2 decimals.
final moneyInputFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

String _two(int n) => n.toString().padLeft(2, '0');

/// 2026-11-05
String formatDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// 2026-11-05 14:07
String formatDateTime(DateTime d) =>
    '${formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}';
