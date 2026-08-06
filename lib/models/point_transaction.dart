class PointTransaction {
  final String id;
  final int amount;
  final String type;
  final String? referenceId;
  final String? description;
  final DateTime createdAt;

  const PointTransaction({
    required this.id,
    required this.amount,
    required this.type,
    this.referenceId,
    this.description,
    required this.createdAt,
  });

  factory PointTransaction.fromJson(Map<String, dynamic> j) {
    DateTime created;
    final raw = j['created_at'] ?? j['createdAt'];
    if (raw is String) {
      created = DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    return PointTransaction(
      id: (j['id'] ?? '').toString(),
      amount: j['amount'] is int ? j['amount'] as int : int.tryParse('${j['amount'] ?? 0}') ?? 0,
      type: (j['type'] ?? '').toString(),
      referenceId: j['reference_id']?.toString() ?? j['referenceId']?.toString(),
      description: j['description']?.toString(),
      createdAt: created,
    );
  }

  bool get isEarn => amount >= 0;
}

class PointsBalance {
  final int balance;
  final int lifetimeEarned;

  const PointsBalance({this.balance = 0, this.lifetimeEarned = 0});

  factory PointsBalance.fromJson(Map<String, dynamic> j) {
    return PointsBalance(
      balance: j['balance'] is int ? j['balance'] as int : int.tryParse('${j['balance'] ?? 0}') ?? 0,
      lifetimeEarned: j['lifetime_earned'] is int
          ? j['lifetime_earned'] as int
          : int.tryParse('${j['lifetime_earned'] ?? 0}') ?? 0,
    );
  }
}

class PaginatedPointTransactions {
  final List<PointTransaction> items;
  final int page;
  final int totalPages;

  const PaginatedPointTransactions({
    required this.items,
    this.page = 1,
    this.totalPages = 1,
  });

  factory PaginatedPointTransactions.fromJson(Map<String, dynamic> j) {
    final itemsRaw = j['items'];
    final items = <PointTransaction>[];
    if (itemsRaw is List) {
      for (final e in itemsRaw) {
        if (e is Map) items.add(PointTransaction.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final pagination = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : <String, dynamic>{};

    return PaginatedPointTransactions(
      items: items,
      page: pagination['page'] is int ? pagination['page'] as int : int.tryParse('${pagination['page'] ?? 1}') ?? 1,
      totalPages: pagination['total_pages'] is int
          ? pagination['total_pages'] as int
          : int.tryParse('${pagination['total_pages'] ?? 1}') ?? 1,
    );
  }

  bool get hasMore => page < totalPages;
}
