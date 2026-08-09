class SyncProgress {
  final double progress; // 0.0 to 1.0
  final String message;
  final bool isComplete;
  final String? error;

  /// A routine background event (an auto-sync finishing again) — screens may
  /// show it, but app-wide toasts stay quiet so silky never becomes noisy.
  final bool subtle;

  const SyncProgress({
    required this.progress,
    required this.message,
    this.isComplete = false,
    this.error,
    this.subtle = false,
  });

  SyncProgress copyWith({
    double? progress,
    String? message,
    bool? isComplete,
    String? error,
    bool? subtle,
  }) {
    return SyncProgress(
      progress: progress ?? this.progress,
      message: message ?? this.message,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
      subtle: subtle ?? this.subtle,
    );
  }

  static const idle = SyncProgress(progress: 0, message: 'Ready');
}
