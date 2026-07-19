class ChatPromptSuggestion {
  const ChatPromptSuggestion({required this.label, required this.message});

  final String label;
  final String message;
}

class ChatEntryContext {
  const ChatEntryContext({
    required this.screenLabel,
    required this.suggestions,
    this.entityType,
    this.entityId,
    this.attachEntityByDefault = false,
    this.initialMessage = '',
  });

  final String screenLabel;
  final List<ChatPromptSuggestion> suggestions;
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
      suggestions: suggestions,
      entityType: entityType,
      entityId: entityId,
      attachEntityByDefault:
          attachEntityByDefault ?? this.attachEntityByDefault,
      initialMessage: initialMessage ?? this.initialMessage,
    );
  }
}
