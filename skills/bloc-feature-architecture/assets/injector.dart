// Target: lib/core/di/injector.dart
import 'package:app/core/di/core_ports_module.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/features/orders/di/orders_module.dart';
import 'package:get_it/get_it.dart';

final sl = GetIt.instance;

/// The composition root: the app's whole object graph in one list. Call once
/// from `main` before `runApp`, with the [ApiClient] adapter built there.
void configureDependencies(
  ApiClient api, {
  PortConfig config = const PortConfig.fromEnvironment(),
}) {
  sl.registerSingleton<ApiClient>(api);
  registerCorePorts(sl, config: config);
  registerOrdersModule(sl);
}
