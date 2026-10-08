// Target: lib/core/crash/crash_reporter_port.dart

/// The app's crash and non-fatal error port.
abstract interface class CrashReporterPort {
  /// [reason] is a short constant label, never user data.
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  });

  /// A breadcrumb. Pass text through `redact` first.
  void log(String message);

  /// Opaque internal id, or null on logout.
  void setUserId(String? userId);
}

final class NoopCrashReporter implements CrashReporterPort {
  const NoopCrashReporter();

  @override
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) {}

  @override
  void log(String message) {}

  @override
  void setUserId(String? userId) {}
}
