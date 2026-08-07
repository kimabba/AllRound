class ClubChatMessage {
  const ClubChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String? senderId;
  final String body;
  final DateTime createdAt;

  factory ClubChatMessage.fromJson(Map<String, dynamic> json) {
    return ClubChatMessage(
      id: json['id'] as String,
      threadId: json['thread_id'] as String,
      senderId: json['sender_id'] as String?,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
