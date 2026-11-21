import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/utils/errors.dart';
import 'package:motor_stock/utils/latest_request.dart';
import 'package:motor_stock/utils/money.dart';
import 'package:motor_stock/utils/paging.dart';
import 'package:motor_stock/utils/period.dart';
import 'package:motor_stock/utils/text.dart';

void main() {
  test('report periods start at local midnight', () {
    final now = DateTime(2026, 11, 22, 15, 30);
    expect(ReportPeriod.today.fromDate(now), DateTime(2026, 11, 22));
    expect(ReportPeriod.week.fromDate(now), DateTime(2026, 11, 16));
    expect(ReportPeriod.month.fromDate(now), DateTime(2026, 10, 24));
    expect(ReportPeriod.all.fromDate(now), isNull);
    // Across a month and year boundary.
    expect(ReportPeriod.week.fromDate(DateTime(2027, 1, 3)), DateTime(2026, 12, 28));
    expect(ReportPeriod.withoutToday, isNot(contains(ReportPeriod.today)));
  });

  test('text helpers', () {
    expect(blankToNull(null), isNull);
    expect(blankToNull('   '), isNull);
    expect(blankToNull('  037 123  '), '037 123');
    expect(cleanSearch(' brake, pad (front)*% '), 'brake  pad  front');
    expect(errorMessage(Exception('Only 2 of Brake pad in stock')),
        'Only 2 of Brake pad in stock');
    expect(errorMessage('plain'), 'plain');
  });

  test('money helpers', () {
    expect(formatDate(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
    expect(formatDateTime(DateTime(2026, 3, 7, 9, 5)), '2026-03-07 09:05');

    TextEditingValue type(String text) => moneyInputFormatter.formatEditUpdate(
        TextEditingValue.empty, TextEditingValue(text: text));
    expect(type('1250.5').text, '1250.5');
    expect(type('12.345').text, '12.34');
    expect(type('-5').text, '');
  });

  test('fetchAllPages reads every page, not just the first 1000 rows', () async {
    final rows = List.generate(2350, (i) => i);
    final asked = <(int, int)>[];
    final all = await fetchAllPages<int>((from, to) async {
      asked.add((from, to));
      return rows.sublist(from, to + 1 > rows.length ? rows.length : to + 1);
    });
    expect(all, rows);
    expect(asked, [(0, 999), (1000, 1999), (2000, 2999)]);
  });

  test('fetchAllPages asks once more when the last page is exactly full', () async {
    var calls = 0;
    final all = await fetchAllPages<int>((from, to) async {
      calls++;
      return from == 0 ? List.filled(3, 1) : <int>[];
    }, pageSize: 3);
    expect(all.length, 3);
    expect(calls, 2);
  });

  test('LatestRequest ignores answers to older requests', () {
    final latest = LatestRequest();
    final first = latest.start();
    expect(latest.isLatest(first), isTrue);
    final second = latest.start();
    expect(latest.isLatest(first), isFalse);
    expect(latest.isLatest(second), isTrue);
  });
}
