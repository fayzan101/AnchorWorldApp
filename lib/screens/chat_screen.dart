import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

import '../models/message.dart';
import '../services/socket_service.dart';
import '../services/message_service.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/fcm_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/open_user_profile.dart';
import '../utils/points_toast.dart';
import '../widgets/safety_dialogs.dart';
import '../widgets/chat_unlock_sheet.dart';
import '../widgets/voice_message_bubble.dart';
import '../models/chat_access.dart';
import '../models/video_call.dart' show CallType;
import '../utils/start_intro_call.dart';
import '../config/api_config.dart';

class _ChatCache {
  final List<Message> messages;
  final List<String> ids;
  final DateTime updatedAt;
  const _ChatCache(this.messages, this.ids, this.updatedAt);
}

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String peerId;
  final String peerName;
  /// Mutual connection required to send. Defaults to true for existing call sites.
  final bool isConnected;

  const ChatScreen({
    Key? key,
    required this.currentUserId,
    required this.peerId,
    required this.peerName,
    this.isConnected = true,
  }) : super(key: key);

  static void clearAllCache() {
    _ChatScreenState._cache.clear();
  }

  /// Drop cached thread for one peer (any direction of cache key).
  static void clearCacheForPeer(String userId, String peerId) {
    _ChatScreenState._cache.remove('$userId->$peerId');
    _ChatScreenState._cache.remove('$peerId->$userId');
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late List<Message> _messages = [];
  final List<String> _messageIds = [];
  late String _myId = '';
  static final Map<String, _ChatCache> _cache = <String, _ChatCache>{};
  static const int _maxCachedThreads = 20;
  String get _cacheKey => '${widget.currentUserId}->${widget.peerId}';
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  bool _loadingMessages = true;
  bool _peerTyping = false;
  bool _typingStartedSent = false;
  Timer? _typingResetTimer;
  Timer? _peerTypingAutoResetTimer;
  bool _peerOnline = false;
  DateTime? _peerLastSeen;
  Timer? _presenceTicker;
  bool? _explicitOnline;
  bool _presenceInitialized = false; // becomes true after first status event
  bool _hasMarkedRead = false;
  ChatAccess? _chatAccess;
  bool _loadingAccess = true;
  final Map<String, Timer> _pendingAcks = {};
  final Map<String, String> _pendingLocalText = {};
  Message? _replyingTo;
  String? _replyingToId;
  StreamSubscription<Map<String, dynamic>>? _newMessageSub;
  StreamSubscription<Map<String, dynamic>>? _userTypingSub;
  StreamSubscription<Map<String, dynamic>>? _userStatusSub;
  StreamSubscription<Map<String, dynamic>>? _messageReadSub;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _messageSentSub;
  StreamSubscription<Map<String, dynamic>>? _messageErrorSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeletedSub;
  StreamSubscription<Map<String, dynamic>>? _chatUnlockedSub;
  StreamSubscription<Map<String, dynamic>>? _messageEditedSub;
  bool _composerFocused = false;
  bool _showEmojiPicker = false;
  bool _recording = false;
  DateTime? _recordStartedAt;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _editingMessageId;

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _myId = widget.currentUserId;
    _resolveCurrentUserId();
    _primeFromCache();
    _loadChatAccess();
    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() => _composerFocused = _focusNode.hasFocus);
    });
    _controller.addListener(_handleTyping);
    _userStatusSub = SocketService().onUserStatusChanged.listen((event) {
      final Map<String, dynamic> payload =
          (event['user'] is Map<String, dynamic>)
              ? Map<String, dynamic>.from(event['user'] as Map)
              : (event['data'] is Map<String, dynamic>)
                  ? Map<String, dynamic>.from(event['data'] as Map)
                  : event;
      final userId = payload['user_id']?.toString() ?? payload['userId']?.toString() ?? payload['id']?.toString();
      if (userId != widget.peerId) return;
      DateTime? lastSeen;
      final ls = payload['last_seen'] ?? payload['lastSeen'] ?? payload['last_active'] ?? payload['lastActive'];
      if (ls is String) {
        try { lastSeen = DateTime.parse(ls); } catch (_) {}
      } else if (ls is int) {
        try {
          lastSeen = (ls > 1000000000000)
              ? DateTime.fromMillisecondsSinceEpoch(ls)
              : DateTime.fromMillisecondsSinceEpoch(ls * 1000);
        } catch (_) {}
      }
      bool? explicitOnline;
      final ioVal = payload['is_online'] ?? payload['online'] ?? payload['isOnline'];
      if (ioVal is bool) {
        explicitOnline = ioVal;
      } else if (ioVal is String) {
        if (ioVal.toLowerCase() == 'true' || ioVal == '1') explicitOnline = true;
        if (ioVal.toLowerCase() == 'false' || ioVal == '0') explicitOnline = false;
      } else if (ioVal is num) {
        explicitOnline = ioVal != 0;
      }
      bool online;
      if (explicitOnline != null) {
        online = explicitOnline;
      } else {
        if (lastSeen != null) {
          final seconds = DateTime.now().difference(lastSeen).inSeconds;
          online = seconds <= 60;
        } else {
          online = false;
        }
      }
      if (mounted) {
        setState(() {
          _explicitOnline = explicitOnline;
          _peerOnline = online;
          if (lastSeen != null) _peerLastSeen = lastSeen;
          _presenceInitialized = true;
        });
      }
    });
  _ensureSocketAndSubscribe();
    _presenceTicker = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (!mounted) return;
      // Keep asking socket for status; never trust REST alone.
      SocketService().requestUserStatus(widget.peerId);
      if (_explicitOnline != null) return;
      if (_peerLastSeen == null) return;
      final seconds = DateTime.now().difference(_peerLastSeen!).inSeconds;
      final newOnline = seconds <= 60;
      if (newOnline != _peerOnline) {
        setState(() => _peerOnline = newOnline);
      }
    });
  _loadFirstPage();
    _messageReadSub = SocketService().onMessageRead.listen((event) {
      final id = event['message_id']?.toString() ?? event['id']?.toString() ?? event['messageId']?.toString();
      if (id == null) return;
      final idx = _messageIds.indexOf(id);
      if (idx >= 0 && idx < _messages.length) {
        final m = _messages[idx];
        if (!m.read) {
          setState(() {
            _messages[idx] = m.copyWith(read: true);
          });
          _saveToCache();
        }
      }
    });
    _userTypingSub = SocketService().onUserTyping.listen((event) {
      try {
        final uid = event['user_id']?.toString() ?? event['userId']?.toString() ?? event['id']?.toString();
        if (uid != widget.peerId) return;
        final raw = event['is_typing'] ?? event['typing'] ?? event['isTyping'];
        bool? isTyping;
        if (raw is bool) {
          isTyping = raw;
        } else if (raw is String) {
          final s = raw.toLowerCase();
          if (s == 'true' || s == '1' || s == 'yes') isTyping = true;
          if (s == 'false' || s == '0' || s == 'no') isTyping = false;
        } else if (raw is num) {
          isTyping = raw != 0;
        }
        if (isTyping == null) return;
        if (!mounted) return;
        setState(() => _peerTyping = isTyping!);
        _peerTypingAutoResetTimer?.cancel();
        if (isTyping == true) {
          _peerTypingAutoResetTimer = Timer(const Duration(seconds: 5), () {
            if (!mounted) return;
            setState(() => _peerTyping = false);
          });
        }
      } catch (_) {}
    });
    _newMessageSub = SocketService().onNewMessage.listen((event) {
      try {
        final fromId = (event['fromId'] ?? event['from_id'] ?? event['sender_id'] ?? event['senderId'] ?? event['from'])?.toString() ?? '';
        final toId   = (event['toId']   ?? event['to_id']   ?? event['receiver_id'] ?? event['receiverId'] ?? event['to'])?.toString() ?? '';
        final isIncomingForThisChat = fromId == widget.peerId && toId == _myId;

        if (!isIncomingForThisChat) return;

        // Peer messaging us means the conversation is open for both — refresh lock state.
        if (_chatAccess?.canMessage != true) {
          _loadChatAccess();
        }

        final id = (event['id'] ?? event['message_id'] ?? event['messageId'] ?? event['_id'])?.toString() ?? '';
        if (id.isEmpty) return; // ignore malformed events
        if (_messageIds.contains(id)) {
          return; // avoid duplicates
        }

        final text = (event['text'] ?? event['content'] ?? event['message'] ?? event['body'])?.toString() ?? '';
        final tsRaw = event['timestamp'] ?? event['created_at'] ?? event['createdAt'] ?? event['sent_at'] ?? event['updated_at'];
        DateTime ts;
        try {
          if (tsRaw is String) {
            ts = DateTime.parse(tsRaw);
          } else if (tsRaw is int) {
            ts = tsRaw > 1000000000000
                ? DateTime.fromMillisecondsSinceEpoch(tsRaw)
                : DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000);
          } else if (tsRaw is num) {
            final iv = tsRaw.toInt();
            ts = iv > 1000000000000
                ? DateTime.fromMillisecondsSinceEpoch(iv)
                : DateTime.fromMillisecondsSinceEpoch(iv * 1000);
          } else {
            ts = DateTime.now();
          }
        } catch (_) {
          ts = DateTime.now();
        }

        final reply = _extractReply(event);
        final msg = Message(
          fromId: fromId,
          toId: toId,
          text: text,
          timestamp: ts,
          read: true,
          replyToMessageId: reply.$1,
          replyToText: reply.$2,
          replyToSenderId: reply.$3,
        );
        if (!mounted) return;
        setState(() {
          _messages.add(msg);
          _messageIds.add(id);
        });

        _saveToCache();
        try {
          FcmService().notifyConversationsUpdated();
        } catch (_) {}
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        if (id.isNotEmpty) {
          SocketService().markAsRead(messageId: id);
        }
      } catch (_) {}
    });
    _messageSentSub = SocketService().onMessageSent.listen((event) {
      try {
        final payload = (event['message'] is Map)
            ? Map<String, dynamic>.from(event['message'] as Map)
            : (event['data'] is Map
                ? Map<String, dynamic>.from(event['data'] as Map)
                : Map<String, dynamic>.from(event));
        final serverMsg = payload;
        final serverId = (serverMsg['id'] ?? serverMsg['message_id'] ?? serverMsg['messageId'] ?? serverMsg['_id'])?.toString() ?? '';
        final serverText = (serverMsg['content'] ?? serverMsg['text'] ?? serverMsg['message'] ?? serverMsg['body'])?.toString() ?? '';
        final senderId = (serverMsg['sender_id'] ?? serverMsg['from_id'] ?? serverMsg['from'])?.toString() ?? '';
        final receiverId = (serverMsg['receiver_id'] ?? serverMsg['to_id'] ?? serverMsg['to'])?.toString() ?? '';
        final clientId = (event['client_message_id'] ?? serverMsg['client_message_id'] ?? event['message_id'])?.toString() ?? '';
        final hasPendingClient = clientId.isNotEmpty && _pendingLocalText.containsKey(clientId);
        // Accept ack for our pending optimistic message even if _myId is still resolving.
        if (!hasPendingClient && senderId.isNotEmpty && senderId != _myId && _myId != 'me') {
          return;
        }
        if (receiverId.isNotEmpty && receiverId != widget.peerId) return;

        String matchedLocalId = '';
        if (clientId.isNotEmpty && _pendingLocalText.containsKey(clientId)) {
          matchedLocalId = clientId;
        } else {
          for (final lid in _pendingLocalText.keys) {
            final txt = _pendingLocalText[lid];
            if (txt != null && txt == serverText) {
              matchedLocalId = lid;
              break;
            }
          }
        }

        int matchIdx = -1;
        if (matchedLocalId.isNotEmpty) {
          matchIdx = _messageIds.indexOf(matchedLocalId);
        }
        if (matchIdx < 0 && serverText.isNotEmpty) {
          for (var i = _messageIds.length - 1; i >= 0; i--) {
            if ((_messageIds[i] == '' || _messageIds[i].startsWith('local-')) &&
                _messages[i].text == serverText &&
                _messages[i].fromId == _myId) {
              matchIdx = i;
              break;
            }
          }
        }

        if (matchIdx >= 0) {
          final existing = _messages[matchIdx];
          DateTime ts = existing.timestamp;
          final tsRaw = serverMsg['created_at'] ?? serverMsg['timestamp'] ?? serverMsg['sent_at'] ?? serverMsg['createdAt'];
          if (tsRaw is String) {
            try {
              ts = DateTime.parse(tsRaw);
            } catch (_) {}
          } else if (tsRaw is int) {
            try {
              ts = tsRaw > 1000000000000
                  ? DateTime.fromMillisecondsSinceEpoch(tsRaw)
                  : DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000);
            } catch (_) {}
          }
          final read = (serverMsg['is_read'] ?? serverMsg['read'] ?? serverMsg['seen']) == true;
          final reply = _extractReply(serverMsg);
          setState(() {
            _messages[matchIdx] = existing.copyWith(
              text: serverText.isNotEmpty ? serverText : existing.text,
              timestamp: ts,
              read: read,
              replyToMessageId: reply.$1 ?? existing.replyToMessageId,
              replyToText: reply.$2 ?? existing.replyToText,
              replyToSenderId: reply.$3 ?? existing.replyToSenderId,
            );
            _messageIds[matchIdx] = serverId.isNotEmpty ? serverId : _messageIds[matchIdx];
          });
          _saveToCache();
          try {
            FcmService().notifyConversationsUpdated();
          } catch (_) {}
        }
        if (matchedLocalId.isNotEmpty) {
          _pendingAcks[matchedLocalId]?.cancel();
          _pendingAcks.remove(matchedLocalId);
          _pendingLocalText.remove(matchedLocalId);
        }
      } catch (_) {}
    });
    _messageErrorSub = SocketService().onMessageError.listen((event) {
      try {
        final clientId = event['client_message_id']?.toString();
        final code = (event['code'] ?? event['error_code'] ?? '').toString().toUpperCase();
        final errText = (event['error'] ?? event['message'] ?? '').toString();
        final lids = clientId != null && clientId.isNotEmpty && _pendingLocalText.containsKey(clientId)
            ? <String>[clientId]
            : List<String>.from(_pendingLocalText.keys);
        for (final lid in lids) {
          _pendingAcks[lid]?.cancel();
          _pendingAcks.remove(lid);
          _pendingLocalText.remove(lid);
          // Remove optimistic bubble on failure
          final idx = _messageIds.indexOf(lid);
          if (idx >= 0) {
            setState(() {
              _messages.removeAt(idx);
              _messageIds.removeAt(idx);
            });
          }
        }
        final locked = code == 'CHAT_LOCKED' ||
            errText.toLowerCase().contains('chat is locked');
        final unavailable = code == 'MESSAGE_UNAVAILABLE' ||
            errText.toLowerCase().contains("couldn't send") ||
            errText.toLowerCase().contains('cannot message');
        if (!mounted) return;
        if (unavailable && _chatAccess?.blockedByMe != true) {
          // Silent / generic — do not reveal that the peer blocked you.
          customSnackBar(
            'Couldn’t send',
            'Message could not be delivered. Try again later.',
            type: SnackType.info,
          );
          return;
        }
        if (_chatAccess?.blockedByMe == true) {
          customSnackBar(
            'Blocked',
            'Unblock this user to send messages.',
            type: SnackType.info,
          );
          return;
        }
        if (locked) {
          _loadChatAccess().then((_) {
            if (!mounted) return;
            // Pair may already be unlocked by the other user — retry silently.
            if (_chatAccess?.canMessage == true) {
              customSnackBar(
                'Ready',
                'Chat is unlocked — try sending again',
                type: SnackType.success,
              );
              return;
            }
            _openUnlockSheet();
          });
          return;
        }
        customSnackBar(
          'Couldn’t send',
          errText.isNotEmpty ? errText : 'Failed to send message',
          type: SnackType.error,
        );
      } catch (_) {}
    });
    _messageDeletedSub = SocketService().onMessageDeleted.listen((event) {
      try {
        final id = (event['message_id'] ?? event['id'])?.toString() ?? '';
        if (id.isEmpty) return;
        final scope = (event['scope'] ?? 'everyone').toString();
        if (scope == 'me') {
          _removeMessageLocally(id);
        } else {
          _applyDeletedForEveryone(id);
        }
      } catch (_) {}
    });
    _chatUnlockedSub = SocketService().onChatUnlocked.listen((event) {
      try {
        final peerId = (event['peer_id'] ?? event['peerId'] ?? '').toString();
        if (peerId.isNotEmpty && peerId != widget.peerId) return;
        _loadChatAccess();
      } catch (_) {}
    });
    _messageEditedSub = SocketService().onMessageEdited.listen((event) {
      try {
        final id = (event['message_id'] ?? event['id'] ?? '').toString();
        if (id.isEmpty) return;
        final text = (event['content'] ?? event['text'] ?? '').toString();
        final editedAtRaw = event['edited_at'] ?? event['editedAt'];
        final editedAt = editedAtRaw != null
            ? DateTime.tryParse('$editedAtRaw')?.toLocal() ?? DateTime.now()
            : DateTime.now();
        _applyEditedLocally(id, text, editedAt);
      } catch (_) {}
    });
  }

  (String?, String?, String?) _extractReply(Map<String, dynamic> j) {
    final nested = j['reply_to'];
    String? id = j['reply_to_message_id']?.toString() ?? j['replyToMessageId']?.toString();
    String? text;
    String? senderId;
    if (nested is Map) {
      id ??= nested['id']?.toString();
      text = nested['content']?.toString() ?? nested['text']?.toString();
      senderId = nested['sender_id']?.toString() ?? nested['senderId']?.toString();
    }
    text ??= j['reply_to_text']?.toString() ?? j['replyToText']?.toString();
    senderId ??= j['reply_to_sender_id']?.toString() ?? j['replyToSenderId']?.toString();
    if (id == null || id.isEmpty) return (null, null, null);
    return (id, text, senderId);
  }

  void _setReplyTarget(Message m, String id) {
    if (id.isEmpty || id.startsWith('local-')) return;
    setState(() {
      _replyingTo = m;
      _replyingToId = id;
    });
    // Bottom sheet / swipe dismiss steal focus; wait until after rebuild + route pop.
    void focusComposer() {
      if (!mounted || !_canCompose) return;
      _focusNode.requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusComposer();
      // Android often needs a second tick after modal/sheet fully closes.
      Future<void>.delayed(const Duration(milliseconds: 120), focusComposer);
    });
  }

  void _clearReply() {
    setState(() {
      _replyingTo = null;
      _replyingToId = null;
    });
  }

  void _applyDeletedForEveryone(String id) {
    final idx = _messageIds.indexOf(id);
    if (idx < 0 || idx >= _messages.length) return;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(
        text: '',
        deletedForEveryone: true,
        replyToText: null,
      );
    });
    _saveToCache();
  }

  void _removeMessageLocally(String id) {
    final idx = _messageIds.indexOf(id);
    if (idx < 0) return;
    setState(() {
      _messages.removeAt(idx);
      _messageIds.removeAt(idx);
      if (_replyingToId == id) {
        _replyingTo = null;
        _replyingToId = null;
      }
    });
    _saveToCache();
  }

  Future<void> _showMessageActions(Message m, String id, bool mine) async {
    if (id.isEmpty || id.startsWith('local-')) return;
    if (m.deletedForEveryone) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.mutedBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: AppColors.primary),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _setReplyTarget(m, id);
                  });
                },
              ),
              if (mine && !m.isVoice)
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startEditMessage(m, id);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.body),
                title: const Text('Delete for me'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _deleteMessage(id, scope: 'me');
                },
              ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
                  title: const Text('Delete for everyone'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: const Text('Delete for everyone?'),
                        content: const Text('This removes the message for both of you.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await _deleteMessage(id, scope: 'everyone');
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessage(String id, {required String scope}) async {
    try {
      await MessageService().deleteMessage(messageId: id, scope: scope);
      if (!mounted) return;
      if (scope == 'me') {
        _removeMessageLocally(id);
      } else {
        _applyDeletedForEveryone(id);
      }
    } catch (e) {
      customSnackBar(
        'Error',
        e.toString().replaceFirst('ApiException: ', ''),
        type: SnackType.error,
      );
    }
  }

  void _startEditMessage(Message m, String id) {
    setState(() {
      _editingMessageId = id;
      _controller.text = m.text;
      _controller.selection = TextSelection.collapsed(offset: m.text.length);
      _replyingTo = null;
      _replyingToId = null;
      _showEmojiPicker = false;
    });
    _focusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessageId = null;
      _controller.clear();
    });
  }

  Future<void> _submitEdit() async {
    final id = _editingMessageId;
    final text = _controller.text.trim();
    if (id == null || text.isEmpty) return;
    try {
      final res = await MessageService().editMessage(messageId: id, content: text);
      if (!mounted) return;
      final newText = (res['content'] ?? text).toString();
      final editedAtRaw = res['edited_at'] ?? res['editedAt'];
      DateTime? editedAt;
      if (editedAtRaw != null) editedAt = DateTime.tryParse('$editedAtRaw')?.toLocal();
      _applyEditedLocally(id, newText, editedAt ?? DateTime.now());
      setState(() {
        _editingMessageId = null;
        _controller.clear();
      });
    } catch (e) {
      customSnackBar(
        'Error',
        e.toString().replaceFirst('ApiException: ', ''),
        type: SnackType.error,
      );
    }
  }

  void _applyEditedLocally(String id, String text, DateTime editedAt) {
    final idx = _messageIds.indexOf(id);
    if (idx < 0) return;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(
        text: text,
        edited: true,
        editedAt: editedAt,
      );
    });
    _saveToCache();
  }

  Future<void> _openEmojiPicker() async {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
    if (_showEmojiPicker) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<bool> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;
    status = await Permission.microphone.request();
    if (status.isGranted) return true;
    customSnackBar('Microphone', 'Allow microphone access to send voice messages', type: SnackType.info);
    return false;
  }

  Future<void> _startRecording() async {
    if (!_canCompose || _sending || _recording || _editingMessageId != null) return;
    if (!await _ensureMicPermission()) return;
    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordStartedAt = DateTime.now();
        _showEmojiPicker = false;
      });
    } catch (e) {
      customSnackBar('Error', 'Could not start recording', type: SnackType.error);
    }
  }

  Future<void> _cancelRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        try { File(path).deleteSync(); } catch (_) {}
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordStartedAt = null;
    });
  }

  Future<void> _stopAndSendRecording() async {
    if (!_recording) return;
    final started = _recordStartedAt;
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordStartedAt = null;
    });
    if (path == null || path.isEmpty) return;
    final durationMs = started == null
        ? null
        : DateTime.now().difference(started).inMilliseconds.clamp(500, 5 * 60 * 1000);
    if (durationMs != null && durationMs < 500) {
      try { File(path).deleteSync(); } catch (_) {}
      customSnackBar('Too short', 'Hold a bit longer to record', type: SnackType.info);
      return;
    }
    await _sendVoice(path, durationMs);
  }

  Future<void> _sendVoice(String filePath, int? durationMs) async {
    if (!_canCompose) return;
    setState(() => _sending = true);
    final localId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    final replyId = _replyingToId;
    final optimistic = Message(
      fromId: _myId,
      toId: widget.peerId,
      text: '',
      timestamp: DateTime.now(),
      replyToMessageId: replyId,
      replyToText: _replyingTo?.text,
      replyToSenderId: _replyingTo?.fromId,
      messageType: 'voice',
      mediaUrl: filePath,
      durationMs: durationMs,
    );
    setState(() {
      _messages.add(optimistic);
      _messageIds.add(localId);
      _replyingTo = null;
      _replyingToId = null;
    });
    _saveToCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      final res = await MessageService().sendVoiceMessage(
        receiverId: widget.peerId,
        filePath: filePath,
        durationMs: durationMs,
        replyToMessageId: replyId,
      );
      if (!mounted) return;
      final mapped = _mapToMessage(res);
      final id = _extractMessageId(res);
      final idx = _messageIds.indexOf(localId);
      setState(() {
        if (idx >= 0) {
          _messages[idx] = mapped;
          if (id.isNotEmpty) _messageIds[idx] = id;
        }
        _sending = false;
      });
      _saveToCache();
    } catch (e) {
      final idx = _messageIds.indexOf(localId);
      if (idx >= 0 && mounted) {
        setState(() {
          _messages.removeAt(idx);
          _messageIds.removeAt(idx);
          _sending = false;
        });
      } else if (mounted) {
        setState(() => _sending = false);
      }
      customSnackBar(
        'Error',
        e.toString().replaceFirst('ApiException: ', ''),
        type: SnackType.error,
      );
    } finally {
      try { File(filePath).deleteSync(); } catch (_) {}
    }
  }

  void _handleTyping() {
    try {
      if (!_typingStartedSent) {
        _typingStartedSent = true;
        SocketService().typingStart(toUserId: widget.peerId);
      }
      _typingResetTimer?.cancel();
      _typingResetTimer = Timer(const Duration(seconds: 2), () {
        _typingStartedSent = false;
        SocketService().typingStop(toUserId: widget.peerId);
      });
    } catch (_) {}
  }

  Future<void> _loadFirstPage() async {
    setState(() => _loadingMessages = true);
    try {
      final prevMessages = List<Message>.from(_messages);
      final prevIds = List<String>.from(_messageIds);

      final res = await MessageService().getMessages(
        userId: widget.peerId,
        page: 1,
        limit: 50,
      );
      final items = (res['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      final msgs = <Message>[];
      final ids = <String>[];
      for (final it in items) {
        final mid = _extractMessageId(it);
        ids.add(mid);
        msgs.add(_mapToMessage(it));
      }
      msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (var i = 0; i < prevMessages.length; i++) {
        final pm = prevMessages[i];
        final pid = i < prevIds.length ? prevIds[i] : '';
        final dedupeId = pid.isNotEmpty ? pid : null;
        final already = dedupeId != null ? ids.contains(dedupeId) : false;
        if (!already) {
          msgs.add(pm);
          ids.add(pid);
        }
      }
      final paired = List.generate(msgs.length, (i) => MapEntry(ids[i], msgs[i]));
      paired.sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      final mergedIds = <String>[];
      final mergedMsgs = <Message>[];
      for (final e in paired) {
        if (e.key.isNotEmpty) {
          if (mergedIds.contains(e.key)) continue;
        }
        mergedIds.add(e.key);
        mergedMsgs.add(e.value);
      }
      if (!mounted) return;
      setState(() {
        _messages = mergedMsgs;
        _messageIds
          ..clear()
          ..addAll(mergedIds);
        _loadingMessages = false;
      });
      _saveToCache();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  await _markAllFromPeerAsRead();
    } catch (e) {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }
  Future<void> _markAllFromPeerAsRead() async {
    if (_messages.isEmpty) return;
    final futures = <Future>[];
    try {
      bool hasUpdates = false;
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (!m.read && m.toId == _myId) {
          final id = (i < _messageIds.length) ? _messageIds[i] : '';
          if (id.isNotEmpty) {
            _messages[i] = m.copyWith(read: true);
            hasUpdates = true;
            try { SocketService().markAsRead(messageId: id); } catch (_) {}
            futures.add(MessageService().markMessageAsRead(messageId: id).catchError((e) {
              return <String, dynamic>{};
            }));
          }
        }
      }
      if (hasUpdates) {
        setState(() {}); // Trigger UI update for optimistic changes
      }
      if (futures.isNotEmpty) {
        _hasMarkedRead = true;
        await Future.wait(futures);
      }
    } catch (e) {}
  }
  Message _mapToMessage(Map<String, dynamic> j) {
    String str(dynamic v) => v?.toString() ?? '';
    bool boolish(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
      return false;
    }
    DateTime parseTs(dynamic v) {
      if (v is String) {
        try { return DateTime.parse(v); } catch (_) {}
      } else if (v is int) {
        try {
          final dt = v > 1000000000000
              ? DateTime.fromMillisecondsSinceEpoch(v)
              : DateTime.fromMillisecondsSinceEpoch(v * 1000);
          return dt.toLocal();
        } catch (_) {}
      } else if (v is num) {
        final iv = v.toInt();
        try {
          final dt = iv > 1000000000000
              ? DateTime.fromMillisecondsSinceEpoch(iv)
              : DateTime.fromMillisecondsSinceEpoch(iv * 1000);
          return dt.toLocal();
        } catch (_) {}
      }
      try {
        return DateTime.parse(v.toString()).toLocal();
      } catch (_) {
        return DateTime.now().toLocal();
      }
    }

    final fromId = str(j['fromId'] ?? j['from_id'] ?? j['senderId'] ?? j['sender_id'] ?? j['from']);
    final toId   = str(j['toId']   ?? j['to_id']   ?? j['receiverId'] ?? j['receiver_id'] ?? j['to']);
    final text   = str(j['text']   ?? j['content'] ?? j['message'] ?? j['body']);
    final read   = boolish(j['read'] ?? j['is_read'] ?? j['seen']);
    final tsRaw  = j['timestamp'] ?? j['created_at'] ?? j['createdAt'] ?? j['sent_at'] ?? j['updated_at'];
    final reply = _extractReply(j);
    final deleted = boolish(j['deleted_for_everyone'] ?? j['deletedForEveryone']) ||
        (j['deleted_at'] != null && '${j['deleted_at']}'.isNotEmpty);
    final editedAtRaw = j['edited_at'] ?? j['editedAt'];
    DateTime? editedAt;
    if (editedAtRaw != null && '$editedAtRaw'.isNotEmpty) {
      editedAt = DateTime.tryParse('$editedAtRaw')?.toLocal();
    }
    final messageType = str(j['message_type'] ?? j['messageType']).isEmpty
        ? 'text'
        : str(j['message_type'] ?? j['messageType']);
    final mediaUrl = str(j['media_url'] ?? j['mediaUrl']);
    final durationRaw = j['duration_ms'] ?? j['durationMs'];
    final durationMs = durationRaw is int
        ? durationRaw
        : int.tryParse('$durationRaw');

    return Message(
      fromId: fromId,
      toId: toId,
      text: deleted ? '' : text,
      read: read,
      timestamp: parseTs(tsRaw),
      replyToMessageId: reply.$1,
      replyToText: deleted ? null : reply.$2,
      replyToSenderId: reply.$3,
      deletedForEveryone: deleted,
      edited: editedAt != null,
      editedAt: editedAt,
      messageType: messageType,
      mediaUrl: deleted || mediaUrl.isEmpty ? null : mediaUrl,
      durationMs: deleted ? null : durationMs,
    );
  }
  String _extractMessageId(Map<String, dynamic> j) {
    final v = j['id'] ?? j['message_id'] ?? j['messageId'] ?? j['_id'];
    return v?.toString() ?? '';
  }
  void _primeFromCache() {
    final cached = _cache[_cacheKey];
    if (cached == null || cached.messages.isEmpty) return;
    // Instant paint from memory; network refresh always follows in initState.
    setState(() {
      _messages = List<Message>.from(cached.messages);
      _messageIds
        ..clear()
        ..addAll(cached.ids);
      _loadingMessages = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _saveToCache() {
    _cache[_cacheKey] = _ChatCache(
      List<Message>.from(_messages),
      List<String>.from(_messageIds),
      DateTime.now(),
    );
    _trimCache();
  }

  void _trimCache() {
    if (_cache.length <= _maxCachedThreads) return;
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.updatedAt.compareTo(b.value.updatedAt));
    final overflow = _cache.length - _maxCachedThreads;
    for (var i = 0; i < overflow; i++) {
      _cache.remove(entries[i].key);
    }
  }

  String _lastSeenString(DateTime dt) {
    final now = DateTime.now();
    final localDt = dt.toLocal();
    final diff = now.difference(localDt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr${diff.inHours > 1 ? 's' : ''} ago';
    return _formatDate(dt);
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')} ${_monthName(local.month)} ${local.year}';
  }

  String _monthName(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }
  Future<void> _resolveCurrentUserId() async {
    try {
      final cached = AuthService().getCachedProfile();
      if (cached != null) {
        final id = (cached['id'] ?? cached['user_id'] ?? cached['userId'])?.toString();
        if (id != null && id.isNotEmpty && id != _myId) {
          setState(() => _myId = id);
        }
        return;
      }
      final profile = await AuthService().getProfile();
      final id = (profile['id'] ?? profile['user_id'] ?? profile['userId'])?.toString();
      if (id != null && id.isNotEmpty && id != _myId) {
        if (!mounted) return;
        setState(() => _myId = id);
      }
    } catch (_) {
    }
  }
  Future<void> _ensureSocketAndSubscribe() async {
    try {
      await SocketService().connect();
      if (!mounted) return;
      SocketService().setActiveChat(widget.peerId);
      SocketService().subscribeUserStatus(widget.peerId);
      SocketService().requestUserStatus(widget.peerId);
      try {
        final profile = await AuthService().getUserById(widget.peerId, forceRefresh: true);
        DateTime? lastSeen;
        final ls = profile['last_seen'] ?? profile['lastSeen'] ?? profile['last_active'] ?? profile['lastActive'];
        if (ls is String) {
          try {
            lastSeen = DateTime.parse(ls);
          } catch (_) {}
        } else if (ls is int) {
          try {
            lastSeen = (ls > 1000000000000)
                ? DateTime.fromMillisecondsSinceEpoch(ls)
                : DateTime.fromMillisecondsSinceEpoch(ls * 1000);
          } catch (_) {}
        }

        bool? explicitOnline;
        final ioVal = profile['is_online'] ?? profile['online'] ?? profile['isOnline'];
        if (ioVal is bool) {
          explicitOnline = ioVal;
        } else if (ioVal is String) {
          if (ioVal.toLowerCase() == 'true' || ioVal == '1') explicitOnline = true;
          if (ioVal.toLowerCase() == 'false' || ioVal == '0') explicitOnline = false;
        } else if (ioVal is num) {
          explicitOnline = ioVal != 0;
        }

        if (!mounted) return;
        if (!_presenceInitialized) {
          setState(() {
            // Seed last-seen only. Do not lock presence from REST —
            // socket user_status_* is the source of truth for Online/Offline.
            if (lastSeen != null) _peerLastSeen = lastSeen;
            if (explicitOnline == true) {
              _peerOnline = true;
            }
          });
        }
      } catch (_) {
      }
      Future.delayed(const Duration(seconds: 12), () {
        if (!mounted || _presenceInitialized) return;
        setState(() {
          _peerOnline = false;
          _presenceInitialized = true;
        });
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _peerOnline = false;
          _presenceInitialized = true;
        });
      }
    }
  }

  Future<void> _loadChatAccess() async {
    if (!widget.isConnected) {
      if (mounted) setState(() => _loadingAccess = false);
      return;
    }
    try {
      final access = await MessageService().getChatAccess(widget.peerId);
      if (!mounted) return;
      setState(() {
        _chatAccess = access;
        _loadingAccess = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Keep prior access if any; don't treat a failed fetch as "unlocked".
      setState(() => _loadingAccess = false);
    }
  }

  bool get _canCompose {
    if (!widget.isConnected) return false;
    if (_loadingAccess) return false;
    final a = _chatAccess;
    if (a == null) return false;
    return a.canMessage;
  }

  Future<void> _openUnlockSheet() async {
    // Always refresh first — peer may have unlocked already.
    await _loadChatAccess();
    if (!mounted) return;
    if (_chatAccess?.canMessage == true) return;

    final updated = await showChatUnlockSheet(
      context: context,
      peerId: widget.peerId,
      peerName: widget.peerName,
      initial: _chatAccess,
    );
    if (updated != null && mounted) {
      setState(() => _chatAccess = updated);
      PointsBalanceBus.notifyChanged(newBalance: updated.myPointsBalance);
    } else {
      await _loadChatAccess();
    }
  }

  Future<void> _showReportDialog() async {
    final reason = await showReportReasonDialog(context, title: 'Report ${widget.peerName}');
    if (reason == null) return;
    try {
      await blockService.reportUser(widget.peerId, reason: reason.isEmpty ? null : reason);
      customSnackBar('Success', 'User reported successfully', type: SnackType.success);
    } catch (e) {
      final errorMsg = e.toString();
      customSnackBar(
        'Error',
        errorMsg.contains('ApiException:') ? errorMsg.replaceFirst('ApiException: ', '') : 'Failed to report user',
        type: SnackType.error,
      );
    }
  }

  Future<void> _blockPeer() async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Block ${widget.peerName}?',
      message: 'They won’t be able to message you. You can unblock them later from this chat.',
      confirmLabel: 'Block',
    );
    if (!ok) return;
    try {
      await blockService.blockUser(widget.peerId);
      if (!mounted) return;
      customSnackBar('Blocked', '${widget.peerName} was blocked', type: SnackType.success);
      await _loadChatAccess();
    } catch (e) {
      customSnackBar('Error', e.toString().replaceFirst('ApiException: ', ''), type: SnackType.error);
    }
  }

  Future<void> _unblockPeer() async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Unblock ${widget.peerName}?',
      message: 'They will be able to message you again if you’re connected.',
      confirmLabel: 'Unblock',
    );
    if (!ok) return;
    try {
      await blockService.unblockUser(widget.peerId);
      if (!mounted) return;
      customSnackBar('Unblocked', '${widget.peerName} was unblocked', type: SnackType.success);
      await _loadChatAccess();
    } catch (e) {
      customSnackBar('Error', e.toString().replaceFirst('ApiException: ', ''), type: SnackType.error);
    }
  }

  String? _peerAvatarUrl() {
    try {
      final cached = AuthService().getCachedUser(widget.peerId);
      if (cached != null) {
        final pic = (cached['profile_picture'] ??
                cached['profile_picture_url'] ??
                cached['picture'] ??
                cached['avatar'] ??
                '')
            .toString()
            .trim();
        if (pic.isNotEmpty) {
          if (pic.startsWith('http')) return pic;
          final base = ApiConfig.baseUrl.replaceAll('/api', '');
          return pic.startsWith('/') ? '$base$pic' : '$base/$pic';
        }
      }
    } catch (_) {}
    return null;
  }

  Widget _peerAvatar() {
    final url = _peerAvatarUrl();
    final initial = widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.white24,
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null
          ? Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))
          : null,
    );
  }

  void _unfocusComposer() {
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _leaveChat() async {
    _unfocusComposer();
    // Let the IME finish closing before the route pops (avoids keyboard on chat list).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    Navigator.of(context).pop({'markedRead': _hasMarkedRead});
  }

  Future<void> _send() async {
    if (_editingMessageId != null) {
      await _submitEdit();
      return;
    }
    final text = _controller.text.trim();
    print('[CHAT] _send called. text="$text" sending=$_sending');
    if (!widget.isConnected) {
      customSnackBar(
        'Connect first',
        'Messaging unlocks when you are mutually connected',
        type: SnackType.info,
      );
      return;
    }
    if (!_canCompose) {
      if (_chatAccess?.blockedByMe == true) {
        await _unblockPeer();
        return;
      }
      await _openUnlockSheet();
      return;
    }
    if (text.isEmpty) {
      print('[CHAT] _send aborted: text is empty');
      return;
    }
    if (_sending) {
      print('[CHAT] _send aborted: already sending another message');
      return;
    }
    var socketConnected = SocketService().isConnected;
    if (!socketConnected) {
      await SocketService().ensureConnection();
      socketConnected = SocketService().isConnected;
    }
    if (!socketConnected) {
      // Prefer chat-lock messaging over a generic "connection" error when locked.
      await _loadChatAccess();
      if (!mounted) return;
      if (_chatAccess?.canMessage != true) {
        if (_chatAccess?.blockedByMe == true) {
          await _unblockPeer();
          return;
        }
        customSnackBar(
          'Chat locked',
          _chatAccess?.reason == 'insufficient_points'
              ? 'You need ${_chatAccess!.chatUnlockCost} points to unlock this chat, or wait for them to unlock it for both of you.'
              : 'This chat is locked. Unlock with points or wait for the other person to unlock it.',
          type: SnackType.info,
        );
        await _openUnlockSheet();
        return;
      }
      customSnackBar(
        'Connection issue',
        'Unable to send message. Check your internet connection and try again.',
        type: SnackType.error,
      );
      return;
    }
    final msg = Message(
      fromId: _myId,
      toId: widget.peerId,
      text: text,
      timestamp: DateTime.now(),
      replyToMessageId: _replyingToId,
      replyToText: _replyingTo?.text,
      replyToSenderId: _replyingTo?.fromId,
    );
    final localId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    final replyId = _replyingToId;
    setState(() {
      _messages.add(msg);
      _messageIds.add(localId);
      _pendingLocalText[localId] = text;
      final paired = List.generate(_messages.length, (i) => MapEntry(_messageIds[i], _messages[i]));
      paired.sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      _messages = paired.map((e) => e.value).toList();
      _messageIds
        ..clear()
        ..addAll(paired.map((e) => e.key));
      _controller.clear();
      _replyingTo = null;
      _replyingToId = null;
      _sending = false;
    });
    _saveToCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    setState(() => _sending = true);
    try {
      SocketService().sendMessage(
        toUserId: widget.peerId,
        content: text,
        messageId: localId,
        replyToMessageId: replyId,
      );
      final t = Timer(const Duration(seconds: 8), () {
        if (_pendingLocalText.containsKey(localId)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Message failed to send'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        _pendingAcks[localId]?.cancel();
        _pendingAcks.remove(localId);
        _pendingLocalText.remove(localId);
      });
      _pendingAcks[localId] = t;
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    _controller.removeListener(_handleTyping);
    _controller.dispose();
    _focusNode.dispose();
    _typingResetTimer?.cancel();
  _peerTypingAutoResetTimer?.cancel();
    _newMessageSub?.cancel();
    _messageSentSub?.cancel();
    _messageErrorSub?.cancel();
    _messageDeletedSub?.cancel();
    _chatUnlockedSub?.cancel();
    _messageEditedSub?.cancel();
    _userTypingSub?.cancel();
    _audioRecorder.dispose();
    _userStatusSub?.cancel();
    _messageReadSub?.cancel();
    for (final t in _pendingAcks.values) {
      t.cancel();
    }
    _pendingAcks.clear();
    _pendingLocalText.clear();
    SocketService().clearActiveChat(widget.peerId);
    SocketService().unsubscribeUserStatus(widget.peerId);
    _presenceTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showLoading = _loadingMessages && _messages.isEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveChat();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(65),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            titleSpacing: 0,
            leadingWidth: 48,
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
            ),
            flexibleSpace: ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.brandGradient,
                  ),
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _leaveChat,
            ),
            title: GestureDetector(
              onTap: () => openUserProfile(
                context,
                userId: widget.peerId,
                fallbackName: widget.peerName,
                isAlreadyConnected: widget.isConnected,
              ),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _peerAvatar(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            _peerTyping
                                ? '${widget.peerName} is typing...'
                                : (!_presenceInitialized
                                    ? 'Checking status…'
                                    : (_peerOnline
                                        ? 'Online'
                                        : (_peerLastSeen != null
                                            ? 'Last seen ${_lastSeenString(_peerLastSeen!)}'
                                            : 'Offline'))),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _peerTyping ? Colors.white : Colors.white70,
                              fontStyle: FontStyle.italic,
                              fontSize: _peerTyping ? 13 : 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Voice call',
                icon: const Icon(Icons.mic_none_rounded, color: Colors.white),
                onPressed: () => startIntroCall(
                  context: context,
                  calleeId: widget.peerId,
                  calleeName: widget.peerName,
                  callType: CallType.voice,
                  isConnected: widget.isConnected,
                ),
              ),
              IconButton(
                tooltip: 'Video call',
                icon: const Icon(Icons.videocam_outlined, color: Colors.white),
                onPressed: () => startIntroCall(
                  context: context,
                  calleeId: widget.peerId,
                  calleeName: widget.peerName,
                  callType: CallType.video,
                  isConnected: widget.isConnected,
                ),
              ),
              PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: Row(
                      children: const [
                        Icon(Icons.mic_none_rounded, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Voice call'),
                      ],
                    ),
                    onTap: () {
                      Future.microtask(
                        () => startIntroCall(
                          context: this.context,
                          calleeId: widget.peerId,
                          calleeName: widget.peerName,
                          callType: CallType.voice,
                          isConnected: widget.isConnected,
                        ),
                      );
                    },
                  ),
                  PopupMenuItem(
                    child: Row(
                      children: const [
                        Icon(Icons.videocam_outlined, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Video call'),
                      ],
                    ),
                    onTap: () {
                      Future.microtask(
                        () => startIntroCall(
                          context: this.context,
                          calleeId: widget.peerId,
                          calleeName: widget.peerName,
                          callType: CallType.video,
                          isConnected: widget.isConnected,
                        ),
                      );
                    },
                  ),
                  PopupMenuItem(
                    child: Row(
                      children: const [
                        Icon(Icons.flag_outlined, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Report User'),
                      ],
                    ),
                    onTap: () => Future.microtask(_showReportDialog),
                  ),
                  PopupMenuItem(
                    child: Row(
                      children: [
                        Icon(
                          _chatAccess?.blockedByMe == true ? Icons.lock_open_rounded : Icons.block,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(_chatAccess?.blockedByMe == true ? 'Unblock User' : 'Block User'),
                      ],
                    ),
                    onTap: () => Future.microtask(
                      _chatAccess?.blockedByMe == true ? _unblockPeer : _blockPeer,
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert, color: Colors.white),
              ),
            ],
            iconTheme: const IconThemeData(color: Colors.white),
          ),
        ),
        body: showLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (!widget.isConnected)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: AppColors.chipIdle,
                      child: const Text(
                        'Connect mutually to send messages in this chat.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    )
                  else if (_chatAccess?.blockedByMe == true)
                    Material(
                      color: AppColors.chipIdle,
                      child: InkWell(
                        onTap: _unblockPeer,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            'You blocked ${widget.peerName} — tap to unblock',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    )
                  else if (!_canCompose &&
                      !_loadingAccess &&
                      (_chatAccess?.reason == 'chat_locked' ||
                          _chatAccess?.reason == 'insufficient_points' ||
                          _chatAccess?.reason == 'slot_limit' ||
                          (_chatAccess?.canUnlock == true)))
                    Material(
                      color: AppColors.chipIdle,
                      child: InkWell(
                        onTap: _openUnlockSheet,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: const Text(
                            'Chat locked — tap to unlock with points (only the unlocker spends). After unlock, both can message.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _unfocusComposer,
                      behavior: HitTestBehavior.opaque,
                      child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      reverse: false,
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final mine = m.fromId == _myId;
                        final showDateHeader = !_loadingMessages && (i == 0 || m.timestamp.day != _messages[i - 1].timestamp.day || m.timestamp.month != _messages[i - 1].timestamp.month || m.timestamp.year != _messages[i - 1].timestamp.year);
                        return Column(
                          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (showDateHeader)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.chipIdle,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      _formatDate(m.timestamp),
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Builder(
                              builder: (context) {
                                final bubble = Container(
                              margin: EdgeInsets.only(top: 4, bottom: 4, left: mine ? 60 : 0, right: mine ? 0 : 60),
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    clipBehavior: Clip.antiAlias,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      gradient: (!m.deletedForEveryone && mine) ? AppColors.brandGradient : null,
                                      color: m.deletedForEveryone
                                          ? AppColors.chipIdle
                                          : (mine ? null : Colors.white),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(20),
                                        topRight: const Radius.circular(20),
                                        bottomLeft: Radius.circular(mine ? 20 : 4),
                                        bottomRight: Radius.circular(mine ? 4 : 20),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: mine && !m.deletedForEveryone
                                              ? AppColors.primary.withOpacity(0.3)
                                              : Colors.black.withOpacity(0.08),
                                          blurRadius: mine ? 12 : 8,
                                          offset: Offset(0, mine ? 4 : 2),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: AppColors.mutedBorder,
                                        width: 1,
                                      ),
                                    ),
                                    constraints: const BoxConstraints(maxWidth: 280),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (m.deletedForEveryone)
                                          const Text(
                                            'This message was deleted',
                                            style: TextStyle(
                                              color: AppColors.body,
                                              fontSize: 14,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          )
                                        else ...[
                                        if (m.replyToText != null && m.replyToText!.isNotEmpty) ...[
                                          Container(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                            decoration: BoxDecoration(
                                              color: mine
                                                  ? Colors.white.withOpacity(0.18)
                                                  : AppColors.primary.withOpacity(0.06),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border(
                                                left: BorderSide(
                                                  color: mine ? Colors.white70 : AppColors.primary,
                                                  width: 3,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  m.replyToSenderId == _myId
                                                      ? 'You'
                                                      : (m.replyToSenderId == widget.peerId
                                                          ? widget.peerName
                                                          : 'Reply'),
                                                  style: TextStyle(
                                                    color: mine ? Colors.white : AppColors.primary,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  m.replyToText!,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: mine ? Colors.white.withOpacity(0.9) : Colors.black54,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (m.isVoice && (m.mediaUrl ?? '').isNotEmpty)
                                          VoiceMessageBubble(
                                            mediaUrl: m.mediaUrl!,
                                            durationMs: m.durationMs,
                                            mine: mine,
                                          )
                                        else
                                          Text(
                                            m.text,
                                            style: TextStyle(
                                              color: mine ? Colors.white : Colors.black87,
                                              fontSize: 15,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (m.edited && !m.deletedForEveryone) ...[
                                              Text(
                                                'Edited',
                                                style: TextStyle(
                                                  color: mine ? Colors.white60 : Colors.black38,
                                                  fontSize: 10,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Text(
                                              _formatTime(m.timestamp),
                                              style: TextStyle(
                                                color: m.deletedForEveryone
                                                    ? AppColors.body
                                                    : (mine ? Colors.white.withOpacity(0.85) : Colors.black45),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (mine && !m.deletedForEveryone) ...[
                                              const SizedBox(width: 3),
                                              Icon(
                                                m.read ? Icons.done_all_rounded : Icons.done_rounded,
                                                size: 14,
                                                color: m.read ? AppColors.accentGold : Colors.white.withOpacity(0.8),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );

                                final interactive = GestureDetector(
                                  onLongPress: () {
                                    final mid = i < _messageIds.length ? _messageIds[i] : '';
                                    _showMessageActions(m, mid, mine);
                                  },
                                  child: m.deletedForEveryone
                                      ? bubble
                                      : Dismissible(
                                          key: ValueKey('reply-${_messageIds.length > i ? _messageIds[i] : i}-$i'),
                                          direction: mine
                                              ? DismissDirection.endToStart
                                              : DismissDirection.startToEnd,
                                          confirmDismiss: (_) async {
                                            final mid = i < _messageIds.length ? _messageIds[i] : '';
                                            _setReplyTarget(m, mid);
                                            return false;
                                          },
                                          background: Align(
                                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              child: Icon(Icons.reply_rounded, color: AppColors.primary.withOpacity(0.7)),
                                            ),
                                          ),
                                          child: bubble,
                                        ),
                                );
                                return interactive;
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyingTo != null && _editingMessageId == null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                            decoration: BoxDecoration(
                              color: AppColors.chipIdle,
                              border: Border(
                                top: BorderSide(color: AppColors.mutedBorder),
                                left: BorderSide(color: AppColors.primary, width: 3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.reply_rounded, color: AppColors.primary, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _replyingTo!.fromId == _myId ? 'Replying to yourself' : 'Replying to ${widget.peerName}',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        _replyingTo!.isVoice ? 'Voice message' : _replyingTo!.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _clearReply,
                                  icon: const Icon(Icons.close, size: 18, color: AppColors.body),
                                ),
                              ],
                            ),
                          ),
                  if (_editingMessageId != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                            decoration: const BoxDecoration(
                              color: AppColors.chipIdle,
                              border: Border(
                                top: BorderSide(color: AppColors.mutedBorder),
                                left: BorderSide(color: AppColors.primary, width: 3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.edit_rounded, color: AppColors.primary, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Editing message',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _cancelEdit,
                                  icon: const Icon(Icons.close, size: 18, color: AppColors.body),
                                ),
                              ],
                            ),
                          ),
                  if (_recording)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            color: AppColors.danger.withOpacity(0.08),
                            child: Row(
                              children: [
                                const Icon(Icons.mic, color: AppColors.danger, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Recording… release to send, slide cancel',
                                    style: TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _cancelRecording,
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ),
                        Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (!_canCompose) {
                                  if (_chatAccess?.blockedByMe == true) {
                                    _unblockPeer();
                                  } else if (widget.isConnected) {
                                    _openUnlockSheet();
                                  }
                                  return;
                                }
                                setState(() => _showEmojiPicker = false);
                                _focusNode.requestFocus();
                              },
                              child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: _composerFocused && _canCompose
                                      ? AppColors.primary
                                      : AppColors.primary.withOpacity(0.2),
                                  width: _composerFocused && _canCompose ? 2 : 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(_composerFocused ? 0.14 : 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: !_canCompose
                                        ? null
                                        : () async {
                                      try {
                                        await _openEmojiPicker();
                                      } catch (e) {}
                                    },
                                    icon: Icon(
                                      _showEmojiPicker
                                          ? Icons.keyboard_alt_outlined
                                          : Icons.emoji_emotions_outlined,
                                      color: AppColors.primary,
                                      size: 24,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _controller,
                                      focusNode: _focusNode,
                                      enabled: _canCompose,
                                      onChanged: (_) => setState(() {}),
                                      onTap: () {
                                        if (_showEmojiPicker) {
                                          setState(() => _showEmojiPicker = false);
                                        }
                                      },
                                      style: const TextStyle(color: Colors.black87, fontSize: 15),
                                      maxLines: null,
                                      textCapitalization: TextCapitalization.sentences,
                                      decoration: InputDecoration(
                                        hintText: _canCompose
                                            ? (_editingMessageId != null
                                                ? 'Edit message...'
                                                : (_replyingTo != null ? 'Write a reply...' : 'Type a message...'))
                                            : (!widget.isConnected
                                                ? 'Connect to message'
                                                : (_chatAccess?.blockedByMe == true
                                                    ? 'Unblock to message'
                                                    : 'Unlock chat to message')),
                                        hintStyle: const TextStyle(color: Colors.black38, fontSize: 15),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(
                              gradient: _recording
                                  ? LinearGradient(colors: [AppColors.danger, AppColors.danger.withOpacity(0.8)])
                                  : AppColors.brandGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_recording ? AppColors.danger : AppColors.primary).withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: Builder(
                                builder: (context) {
                                  final hasText = _controller.text.trim().isNotEmpty;
                                  final showMic = _canCompose &&
                                      !hasText &&
                                      _editingMessageId == null &&
                                      !_sending;
                                  return GestureDetector(
                                    onTap: _sending
                                        ? null
                                        : () {
                                            if (_editingMessageId != null || hasText) {
                                              _send();
                                            }
                                          },
                                    onLongPressStart: showMic
                                        ? (_) => _startRecording()
                                        : null,
                                    onLongPressEnd: showMic || _recording
                                        ? (_) => _stopAndSendRecording()
                                        : null,
                                    child: InkWell(
                                      onTap: _sending
                                          ? null
                                          : () {
                                              if (_editingMessageId != null || hasText) {
                                                _send();
                                              } else if (showMic) {
                                                customSnackBar(
                                                  'Voice message',
                                                  'Hold the mic to record',
                                                  type: SnackType.info,
                                                );
                                              }
                                            },
                                      customBorder: const CircleBorder(),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        alignment: Alignment.center,
                                        child: Icon(
                                          _editingMessageId != null
                                              ? Icons.check_rounded
                                              : (showMic || _recording
                                                  ? Icons.mic_rounded
                                                  : Icons.send_rounded),
                                          color: _sending ? Colors.white.withOpacity(0.5) : Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                      if (_showEmojiPicker)
                        SizedBox(
                          height: 280,
                          child: EmojiPicker(
                            textEditingController: _controller,
                            onEmojiSelected: (category, emoji) {
                              setState(() {});
                            },
                            config: Config(
                              height: 280,
                              checkPlatformCompatibility: true,
                              emojiViewConfig: EmojiViewConfig(
                                emojiSizeMax: 28 *
                                    (foundation.defaultTargetPlatform == TargetPlatform.iOS ? 1.2 : 1.0),
                                backgroundColor: Colors.white,
                              ),
                              skinToneConfig: const SkinToneConfig(),
                              categoryViewConfig: const CategoryViewConfig(
                                indicatorColor: AppColors.primary,
                                iconColorSelected: AppColors.primary,
                              ),
                              bottomActionBarConfig: const BottomActionBarConfig(
                                backgroundColor: Colors.white,
                                buttonColor: AppColors.primary,
                              ),
                              searchViewConfig: const SearchViewConfig(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
      ),
    );
  }
}
