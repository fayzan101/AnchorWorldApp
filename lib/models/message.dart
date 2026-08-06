class Message {
  final String fromId;
  final String toId;
  final String text;
  final bool read;
  final DateTime timestamp;
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderId;
  final bool deletedForEveryone;
  final bool edited;
  final DateTime? editedAt;
  final String messageType; // text | voice
  final String? mediaUrl;
  final int? durationMs;

  Message({
    required this.fromId,
    required this.toId,
    required this.text,
    required this.timestamp,
    this.read = false,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderId,
    this.deletedForEveryone = false,
    this.edited = false,
    this.editedAt,
    this.messageType = 'text',
    this.mediaUrl,
    this.durationMs,
  });

  bool get isVoice => messageType == 'voice';

  Message copyWith({
    String? fromId,
    String? toId,
    String? text,
    bool? read,
    DateTime? timestamp,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderId,
    bool? deletedForEveryone,
    bool? edited,
    DateTime? editedAt,
    String? messageType,
    String? mediaUrl,
    int? durationMs,
  }) {
    return Message(
      fromId: fromId ?? this.fromId,
      toId: toId ?? this.toId,
      text: text ?? this.text,
      read: read ?? this.read,
      timestamp: timestamp ?? this.timestamp,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToText: replyToText ?? this.replyToText,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      edited: edited ?? this.edited,
      editedAt: editedAt ?? this.editedAt,
      messageType: messageType ?? this.messageType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'fromId': fromId,
        'toId': toId,
        'text': text,
        'read': read,
        'timestamp': timestamp.toIso8601String(),
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (replyToText != null) 'replyToText': replyToText,
        if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
        'deletedForEveryone': deletedForEveryone,
        'edited': edited,
        if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
        'messageType': messageType,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (durationMs != null) 'durationMs': durationMs,
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        fromId: j['fromId'] as String,
        toId: j['toId'] as String,
        text: j['text'] as String,
        read: j['read'] as bool? ?? false,
        timestamp: DateTime.parse(j['timestamp'] as String),
        replyToMessageId: j['replyToMessageId'] as String?,
        replyToText: j['replyToText'] as String?,
        replyToSenderId: j['replyToSenderId'] as String?,
        deletedForEveryone: j['deletedForEveryone'] as bool? ?? false,
        edited: j['edited'] as bool? ?? false,
        editedAt: j['editedAt'] != null ? DateTime.tryParse('${j['editedAt']}') : null,
        messageType: (j['messageType'] ?? 'text').toString(),
        mediaUrl: j['mediaUrl'] as String?,
        durationMs: j['durationMs'] is int ? j['durationMs'] as int : int.tryParse('${j['durationMs'] ?? ''}'),
      );
}
