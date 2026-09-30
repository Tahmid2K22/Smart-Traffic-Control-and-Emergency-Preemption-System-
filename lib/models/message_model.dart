// Dart model that maps to the Supabase `messages` table.

enum SenderRole {
  user,
  driver;

  static SenderRole fromString(String value) =>
      value == 'driver' ? SenderRole.driver : SenderRole.user;

  String toDbString() => name; // 'user' or 'driver'
}

class ChatMessage {
  final String id;
  final String requestId;
  final SenderRole senderRole;
  final String senderName;
  final String body;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.requestId,
    required this.senderRole,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id:         map['id'] as String,
        requestId:  map['request_id'] as String,
        senderRole: SenderRole.fromString(map['sender_role'] as String),
        senderName: map['sender_name'] as String,
        body:       map['body'] as String,
        createdAt:  DateTime.parse(map['created_at'] as String).toLocal(),
      );

  Map<String, dynamic> toInsertMap() => {
        'request_id':   requestId,
        'sender_role':  senderRole.toDbString(),
        'sender_name':  senderName,
        'body':         body,
      };

  bool get isUser   => senderRole == SenderRole.user;
  bool get isDriver => senderRole == SenderRole.driver;
}
