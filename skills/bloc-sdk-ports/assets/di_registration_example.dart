// Target: lib/core/di/core_ports_module.dart
import 'package:app/core/analytics/analytics_port.dart';
import 'package:app/core/analytics/fan_out_analytics.dart';
import 'package:app/core/analytics/noop_analytics.dart';
import 'package:app/core/crash/crash_reporter_port.dart';
import 'package:app/core/platform/share_port.dart';
import 'package:app/core/platform/url_launcher_port.dart';
import 'package:get_it/get_it.dart';

/// Build-time switches, set per flavor with `--dart-define`.
final class PortConfig {
  const PortConfig({
    required this.analyticsEnabled,
    required this.crashReportingEnabled,
  });

  const PortConfig.fromEnvironment()
    : analyticsEnabled = const bool.fromEnvironment('ANALYTICS_ENABLED'),
      crashReportingEnabled = const bool.fromEnvironment(
        'CRASH_REPORTING_ENABLED',
      );

  final bool analyticsEnabled;
  final bool crashReportingEnabled;
}

/// Registers every SDK port as its PORT type, so nothing outside this file
/// and the adapters knows which vendor is behind it.
///
/// [analyticsVendors] and [crashReporter] are adapters the entry point built
/// after their SDKs initialised; pass none when init failed and the app runs
/// on no-ops.
void registerCorePorts(
  GetIt sl, {
  required PortConfig config,
  List<AnalyticsPort> analyticsVendors = const [],
  CrashReporterPort? crashReporter,
}) {
  sl
    ..registerLazySingleton<AnalyticsPort>(
      () => config.analyticsEnabled && analyticsVendors.isNotEmpty
          ? FanOutAnalytics(analyticsVendors)
          : const NoopAnalytics(),
    )
    ..registerLazySingleton<CrashReporterPort>(
      () => config.crashReportingEnabled && crashReporter != null
          ? crashReporter
          : const NoopCrashReporter(),
    )
    ..registerLazySingleton<UrlLauncherPort>(() => const UrlLauncherAdapter())
    ..registerLazySingleton<SharePort>(() => const SharePlusAdapter());
}
