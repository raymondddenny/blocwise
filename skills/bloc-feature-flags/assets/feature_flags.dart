// Target: lib/core/flags/feature_flags.dart
import 'dart:convert';

import 'package:app/core/flags/flag_defaults.dart';
import 'package:flutter/foundation.dart';

/// Vendor adapter (Firebase, PostHog, LaunchDarkly, Statsig, your own API).
///
/// Returns the current value for each of [keys] the vendor knows. Keys it does
/// not know (deleted, deactivated, not targeted) are simply absent; the
/// adapter never invents a value for them.
abstract interface class FlagsSourcePort {
  Future<Map<String, Object?>> fetch(Iterable<String> keys);
}

/// Synchronous flag reads over the last fetched snapshot, falling back to
/// [flagDefaults] per key. Listeners fire when a reload changes the snapshot.
///
/// Register once as a singleton; call [reload] on cold start, after login,
/// on app resume and from a foreground poll.
class FeatureFlags extends ChangeNotifier {
  FeatureFlags(this._source, {this.defaults = flagDefaults, this.onError});

  final FlagsSourcePort _source;
  final Map<String, Object> defaults;

  /// Called when a fetch fails, e.g. to log or report it.
  final void Function(Object error, StackTrace stack)? onError;
  Map<String, Object?> _snapshot = const {};
  Future<void>? _inFlight;

  /// Fetches a fresh snapshot. Overlapping calls (resume during a poll) share
  /// one fetch. A failed fetch keeps the previous snapshot, never the empty
  /// one, so a flaky network cannot flip flags back to their defaults.
  Future<void> reload() =>
      _inFlight ??= _reload().whenComplete(() => _inFlight = null);

  Future<void> _reload() async {
    final Map<String, Object?> next;
    try {
      next = Map.unmodifiable(await _source.fetch(defaults.keys));
    } catch (error, stack) {
      onError?.call(error, stack);
      return;
    }
    // Shallow compare: a JSON value delivered as a Map notifies on
    // every reload. Use DeepCollectionEquality if that ever matters.
    if (mapEquals(next, _snapshot)) return;
    _snapshot = next;
    notifyListeners();
  }

  /// Accepts a real bool or the strings `true` / `false` (some vendors only
  /// deliver strings). Anything else falls back to the default.
  bool getBool(String key) => switch (_snapshot[key]) {
    final bool value => value,
    'true' => true,
    'false' => false,
    _ => _default<bool>(key),
  };

  String getString(String key) => switch (_snapshot[key]) {
    final String value => value,
    _ => _default<String>(key),
  };

  /// A comma-separated list flag as trimmed, non-empty entries.
  List<String> getList(String key) => [
    for (final item in getString(key).split(','))
      if (item.trim().isNotEmpty) item.trim(),
  ];

  /// A JSON object flag, delivered either decoded or as a string. Malformed
  /// remote JSON falls back to the default rather than half-applying.
  Map<String, Object?> getJson(String key) =>
      _asJsonObject(_snapshot[key]) ??
      _asJsonObject(_default<Object>(key)) ??
      const {};

  /// An experiment arm. Anything outside [arms] (typo, retired arm, missing
  /// flag) is `control`, so a bad console edit never shows an untested UI.
  String getVariant(String key, Set<String> arms) {
    final value = getString(key);
    return arms.contains(value) ? value : 'control';
  }

  T _default<T extends Object>(String key) {
    final value = defaults[key];
    if (value is T) return value;
    // Only reachable for a key missing from flagDefaults (a test guards this).
    throw ArgumentError.value(key, 'key', 'no $T default in flagDefaults');
  }

  static Map<String, Object?>? _asJsonObject(Object? raw) {
    if (raw is Map<String, Object?>) return raw;
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
