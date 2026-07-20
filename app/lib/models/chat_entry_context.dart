class ChatEntryContext {
  const ChatEntryContext({
    required this.screenLabel,
    this.entityType,
    this.entityId,
    this.attachEntityByDefault = false,
    this.initialMessage = '',
  });

  final String screenLabel;
  final String? entityType;
  final String? entityId;
  final bool attachEntityByDefault;
  final String initialMessage;

  bool get canAttachEntity => entityType != null && entityId != null;

  ChatEntryContext copyWith({
    bool? attachEntityByDefault,
    String? initialMessage,
  }) {
    return ChatEntryContext(
      screenLabel: screenLabel,
      entityType: entityType,
      entityId: entityId,
      attachEntityByDefault:
          attachEntityByDefault ?? this.attachEntityByDefault,
      initialMessage: initialMessage ?? this.initialMessage,
    );
  }
}
