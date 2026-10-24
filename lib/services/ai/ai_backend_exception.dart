enum AiFailureKind {
  timeout,
  unavailable,
  quota,
  authorization,
  invalidInput,
  invalidResponse,
  configuration,
}

/// Stable failures shared by every AI feature; callers never parse provider text.
class AiBackendException implements Exception {
  const AiBackendException(
    this.kind,
    this.message, {
    this.retryable = false,
    this.requestId,
    this.retryAfter,
  });
  final AiFailureKind kind;
  final String message;
  final bool retryable;
  final String? requestId;
  final Duration? retryAfter;

  factory AiBackendException.fromResponse(int status, Object? details) {
    final data = details is Map ? details : const <String, Object?>{};
    final kind = switch (data['code']) {
      'quota' => AiFailureKind.quota,
      'authorization' => AiFailureKind.authorization,
      'invalid_input' => AiFailureKind.invalidInput,
      'invalid_response' => AiFailureKind.invalidResponse,
      'configuration' => AiFailureKind.configuration,
      'timeout' => AiFailureKind.timeout,
      'unavailable' => AiFailureKind.unavailable,
      _ => switch (status) {
        401 || 403 => AiFailureKind.authorization,
        429 => AiFailureKind.quota,
        400 || 413 || 422 => AiFailureKind.invalidInput,
        408 || 504 => AiFailureKind.timeout,
        _ => AiFailureKind.unavailable,
      },
    };
    final fallback = switch (kind) {
      AiFailureKind.quota =>
        "Today's AI requests are used up. Try again tomorrow.",
      AiFailureKind.authorization => 'Please sign in again to use Herculex AI.',
      AiFailureKind.invalidInput => 'Please check your input and try again.',
      AiFailureKind.timeout =>
        'Herculex AI took too long. Your input is kept; please try again.',
      _ =>
        'Herculex AI is temporarily unavailable. Your input is kept; please try again.',
    };
    final message = data['error'];
    final seconds = data['retryAfterSeconds'];
    return AiBackendException(
      kind,
      message is String && message.trim().isNotEmpty ? message : fallback,
      retryable: data['retryable'] is bool
          ? data['retryable'] as bool
          : const {
              AiFailureKind.timeout,
              AiFailureKind.unavailable,
              AiFailureKind.invalidResponse,
            }.contains(kind),
      requestId: data['requestId'] is String
          ? data['requestId'] as String
          : null,
      retryAfter: seconds is num && seconds.isFinite && seconds >= 0
          ? Duration(milliseconds: (seconds * 1000).round())
          : null,
    );
  }

  @override
  String toString() => message;
}
