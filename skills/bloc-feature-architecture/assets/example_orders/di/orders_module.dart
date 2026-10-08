// Target: lib/features/orders/di/orders_module.dart
import 'package:app/core/analytics/analytics_port.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/features/orders/data/orders_api.dart';
import 'package:app/features/orders/data/orders_repository_impl.dart';
import 'package:app/features/orders/domain/orders_repository.dart';
import 'package:app/features/orders/presentation/cubit/orders_cubit.dart';
import 'package:app/features/orders/presentation/cubit/place_order_cubit.dart';
import 'package:get_it/get_it.dart';

/// Repositories are lazy singletons registered as their contract; cubits are
/// factories, because a singleton cubit outlives its page.
void registerOrdersModule(GetIt sl) {
  sl
    ..registerLazySingleton<OrdersApi>(() => OrdersApi(sl<ApiClient>()))
    ..registerLazySingleton<OrdersRepository>(
      () => OrdersRepositoryImpl(sl<OrdersApi>()),
    )
    ..registerFactory<OrdersCubit>(() => OrdersCubit(sl<OrdersRepository>()))
    ..registerFactory<PlaceOrderCubit>(
      () => PlaceOrderCubit(sl<OrdersRepository>(), sl<AnalyticsPort>()),
    );
}
