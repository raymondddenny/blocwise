// Target: lib/core/money/transaction_status.dart

/// Where a money movement stands, as far as the app can tell.
enum TransactionOutcome {
  succeeded,
  failed,
  pending,

  /// A status string the app does not recognise. Render it like [pending]
  /// and log it; never like [succeeded].
  unknown;

  bool get isTerminal => this == succeeded || this == failed;
}

/// Classifies backend status strings with explicit lists. Only an allowlisted
/// status is a success; anything new or misspelled stays non-terminal.
final class TransactionStatusClassifier {
  const TransactionStatusClassifier({
    required this.succeeded,
    required this.failed,
    this.pending = const {},
  });

  /// Lowercase status strings.
  final Set<String> succeeded;
  final Set<String> failed;
  final Set<String> pending;

  TransactionOutcome classify(String? raw) {
    final status = raw?.trim().toLowerCase() ?? '';
    if (succeeded.contains(status)) return TransactionOutcome.succeeded;
    if (failed.contains(status)) return TransactionOutcome.failed;
    if (pending.contains(status)) return TransactionOutcome.pending;
    return TransactionOutcome.unknown;
  }
}
