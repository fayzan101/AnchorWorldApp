import '../screens/chat_screen.dart';
import '../screens/chats_list_screen.dart';

/// Central invalidation for in-memory chat caches.
class ChatCaches {
  ChatCaches._();

  static void clearConversationList() {
    ChatsListScreen.clearCache();
  }

  static void clearAllThreads() {
    ChatScreen.clearAllCache();
  }

  static void clearThread(String userId, String peerId) {
    ChatScreen.clearCacheForPeer(userId, peerId);
  }

  /// Call on logout / account switch.
  static void clearAll() {
    clearConversationList();
    clearAllThreads();
  }
}
