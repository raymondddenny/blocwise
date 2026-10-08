// Target: lib/core/platform/url_launcher_port.dart
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens URLs outside the app. Returns false when the URL was refused or
/// nothing could open it.
abstract interface class UrlLauncherPort {
  Future<bool> open(Uri uri, {bool inApp = false});
}

/// The only file that imports url_launcher.
///
/// URLs often come from servers, push payloads or deep links, so the scheme
/// is allowlisted: `javascript:`, `file:`, `intent:` and custom schemes of
/// other apps are refused here, once, instead of at every call site.
final class UrlLauncherAdapter implements UrlLauncherPort {
  const UrlLauncherAdapter({
    this.allowedSchemes = const {'https', 'mailto', 'tel'},
    this.allowedHosts,
  });

  /// Lowercase schemes.
  final Set<String> allowedSchemes;

  /// When set, http(s) URLs must have one of these hosts (or a subdomain).
  final Set<String>? allowedHosts;

  bool isAllowed(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (!allowedSchemes.contains(scheme)) return false;
    final hosts = allowedHosts;
    if (hosts == null || (scheme != 'https' && scheme != 'http')) return true;
    final host = uri.host.toLowerCase();
    return hosts.any((h) => host == h || host.endsWith('.$h'));
  }

  @override
  Future<bool> open(Uri uri, {bool inApp = false}) async {
    if (!isAllowed(uri)) return false;
    try {
      return await launchUrl(
        uri,
        mode: inApp
            ? LaunchMode.inAppBrowserView
            : LaunchMode.externalApplication,
      );
    } on PlatformException {
      return false;
    }
  }
}
