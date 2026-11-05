/// A shop branch that holds its own stock.
class Branch {
  final String id;
  final String name;
  final bool isMain;
  // Printed on bills.
  final String? address;
  final String? phone;

  const Branch({
    required this.id,
    required this.name,
    this.isMain = false,
    this.address,
    this.phone,
  });

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
        id: json['id'] as String,
        name: json['name'] as String,
        isMain: json['is_main'] as bool? ?? false,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
      );
}

/// One logged movement of stock from one branch to another.
class StockTransfer {
  final String id;
  final String partName;
  final String? partNo;
  final String fromBranch;
  final String toBranch;
  final int quantity;
  final String? note;
  final DateTime createdAt;

  const StockTransfer({
    required this.id,
    required this.partName,
    this.partNo,
    required this.fromBranch,
    required this.toBranch,
    required this.quantity,
    this.note,
    required this.createdAt,
  });

  static const selectColumns = 'id, quantity, note, created_at, '
      'part:part_id(name, part_no), '
      'from_branch:from_branch_id(name), to_branch:to_branch_id(name)';

  factory StockTransfer.fromJson(Map<String, dynamic> json) {
    final part = json['part'] as Map<String, dynamic>?;
    String branchName(String key) =>
        (json[key] as Map<String, dynamic>?)?['name'] as String? ?? '?';
    return StockTransfer(
      id: json['id'] as String,
      partName: part?['name'] as String? ?? '(deleted part)',
      partNo: part?['part_no'] as String?,
      fromBranch: branchName('from_branch'),
      toBranch: branchName('to_branch'),
      quantity: (json['quantity'] as num).toInt(),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
