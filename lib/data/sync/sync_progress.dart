class SyncProgress {
  final double progress; // 0.0 to 1.0
  final String message;
  final bool isComplete;
  final String? error;

  const SyncProgress({
    required this.progress,
    required this.message,
    this.isComplete = false,
    this.error,
  });

  SyncProgress copyWith({
    double? progress,
    String? message,
    bool? isComplete,
    String? error,
  }) {
    return SyncProgress(
      progress: progress ?? this.progress,
      message: message ?? this.message,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
    );
  }

  static const idle = SyncProgress(progress: 0, message: 'Ready');
}
