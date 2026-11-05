import 'package:flutter/material.dart';

import '../models/branch.dart';
import '../services/branch_service.dart';

/// Recent stock transfers between branches, newest first.
class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  final _service = BranchService();
  List<StockTransfer> _transfers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final transfers = await _service.fetchTransfers();
      if (mounted) {
        setState(() {
          _transfers = transfers;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load transfers: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _transfers.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text('No transfers yet')),
                        ])
                      : ListView.separated(
                          itemCount: _transfers.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) => _tile(_transfers[i]),
                        ),
                ),
    );
  }

  Widget _tile(StockTransfer t) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Text('${t.quantity}',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSecondaryContainer)),
      ),
      title: Text([t.partName, t.partNo].whereType<String>().join(' • ')),
      subtitle: Text(
        '${t.fromBranch} → ${t.toBranch}\n'
        '${_formatDate(t.createdAt)}'
        '${t.note == null ? '' : ' • ${t.note}'}',
      ),
      isThreeLine: true,
    );
  }
}
