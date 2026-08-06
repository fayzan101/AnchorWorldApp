class ChatAccess {
  final bool connected;
  final bool blocked;
  final bool blockedByMe;
  final bool blockedByPeer;
  final String plan;
  final bool hasUnlimitedChat;
  final bool unlocked;
  final bool canMessage;
  final bool canUnlock;
  final int chatUnlockCost;
  final int chatSlotsUsed;
  final int? chatSlotsMax;
  final int myPointsBalance;
  final int peerPointsBalance;
  final bool peerHasEnoughPoints;
  final String? reason;

  const ChatAccess({
    required this.connected,
    required this.blocked,
    this.blockedByMe = false,
    this.blockedByPeer = false,
    required this.plan,
    required this.hasUnlimitedChat,
    required this.unlocked,
    required this.canMessage,
    required this.canUnlock,
    required this.chatUnlockCost,
    required this.chatSlotsUsed,
    this.chatSlotsMax,
    required this.myPointsBalance,
    required this.peerPointsBalance,
    required this.peerHasEnoughPoints,
    this.reason,
  });

  factory ChatAccess.fromJson(Map<String, dynamic> j) {
    final maxRaw = j['chat_slots_max'];
    final blockedByMe = j['blocked_by_me'] == true || j['blocked'] == true;
    final blockedByPeer = j['blocked_by_peer'] == true;
    return ChatAccess(
      connected: j['connected'] == true,
      blocked: blockedByMe,
      blockedByMe: blockedByMe,
      blockedByPeer: blockedByPeer,
      plan: (j['plan'] ?? 'free').toString(),
      hasUnlimitedChat: j['has_unlimited_chat'] == true,
      unlocked: j['unlocked'] == true,
      canMessage: j['can_message'] == true,
      canUnlock: j['can_unlock'] == true,
      chatUnlockCost: int.tryParse('${j['chat_unlock_cost'] ?? 50}') ?? 50,
      chatSlotsUsed: int.tryParse('${j['chat_slots_used'] ?? 0}') ?? 0,
      chatSlotsMax: maxRaw == null ? null : int.tryParse('$maxRaw'),
      myPointsBalance: int.tryParse('${j['my_points_balance'] ?? 0}') ?? 0,
      peerPointsBalance: int.tryParse('${j['peer_points_balance'] ?? 0}') ?? 0,
      peerHasEnoughPoints: j['peer_has_enough_points'] == true,
      reason: j['reason']?.toString(),
    );
  }
}
