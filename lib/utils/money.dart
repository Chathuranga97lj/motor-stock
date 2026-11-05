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

/// 2026-11-05 14:07
String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
