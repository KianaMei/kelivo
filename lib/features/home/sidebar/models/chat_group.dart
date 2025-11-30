import '../../../../core/models/chat_item.dart';

/// Groups conversations by date label (Today, Yesterday, etc.)
class ChatGroup {
  final String label;
  final List<ChatItem> items;

  ChatGroup({required this.label, required this.items});
}
