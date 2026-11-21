import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/stock_return.dart';
import '../theme.dart';
import '../utils/money.dart';

/// The "Returned" card on a bill or stock-in: one entry per return.
class ReturnsSection extends StatelessWidget {
  const ReturnsSection({super.key, required this.returns});

  final List<StockReturn> returns;

  @override
  Widget build(BuildContext context) {
    if (returns.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: 'Returned',
      icon: Icons.assignment_return_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, r) in returns.indexed) ...[
            if (i > 0) const Divider(height: 20),
            ReturnSummary(ret: r),
          ],
        ],
      ),
    );
  }
}

/// One return: items, value, reason, refund, who and when.
class ReturnSummary extends StatelessWidget {
  const ReturnSummary({super.key, required this.ret, this.showDoc = false});

  final StockReturn ret;

  /// Show the bill / stock-in number and customer / supplier (history list).
  final bool showDoc;

  @override
  Widget build(BuildContext context) {
    final customer = ret.kind == ReturnKind.customer;
    final money = ret.refundAmount > 0
        ? customer
            ? 'Refunded ${formatMoney(ret.refundAmount)} by ${ret.refundMethod?.label ?? 'cash'}'
            : 'Supplier refunded ${formatMoney(ret.refundAmount)} by ${ret.refundMethod?.label ?? 'cash'}'
        : customer
            ? 'Taken off what the customer owes'
            : 'Taken off what is owed to the supplier';
    final owedCut = roundMoney(ret.value - ret.refundAmount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                showDoc
                    ? [ret.docNo ?? '', if (ret.otherParty != null) ret.otherParty!]
                        .where((s) => s.isNotEmpty)
                        .join(' • ')
                    : '${ret.itemCount} ${ret.itemCount == 1 ? 'item' : 'items'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              formatMoney(ret.value),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Brand.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        for (final item in ret.items)
          Text(
            '${item.quantity} × ${item.name}'
            '${item.partNo == null ? '' : ' (${item.partNo})'}',
          ),
        const SizedBox(height: 2),
        Text('Reason: ${ret.reason}',
            style: const TextStyle(color: Brand.muted, fontSize: 13)),
        Text(
          ret.refundAmount > 0 && owedCut > 0
              ? '$money • ${formatMoney(owedCut)} off the balance'
              : money,
          style: const TextStyle(color: Brand.muted, fontSize: 13),
        ),
        Text(
          [formatDateTime(ret.createdAt), if (ret.by != null) ret.by!].join(' • '),
          style: const TextStyle(color: Brand.muted, fontSize: 12),
        ),
      ],
    );
  }
}
