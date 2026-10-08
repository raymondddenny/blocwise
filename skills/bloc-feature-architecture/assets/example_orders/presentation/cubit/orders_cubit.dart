// Target: lib/features/orders/presentation/cubit/orders_cubit.dart
import 'package:app/core/bloc/safe_emit.dart';
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/result/result.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:app/features/orders/domain/orders_repository.dart';
import 'package:app/features/orders/presentation/cubit/orders_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class OrdersCubit extends Cubit<OrdersState> with SafeEmit<OrdersState> {
  OrdersCubit(this._repository) : super(const OrdersState());

  final OrdersRepository _repository;

  /// Bumped by every load and refresh. A response whose generation is no
  /// longer current belongs to a list the user has already replaced.
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    safeEmit(
      state.copyWith(
        status: OrdersStatus.loading,
        isRefreshing: false,
        isLoadingMore: false,
        failure: () => null,
      ),
    );
    final result = await _repository.fetchOrders(page: 1);
    if (generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        safeEmit(_firstPage(value));
      case Err(:final failure):
        _report(failure);
        safeEmit(
          state.copyWith(status: OrdersStatus.failure, failure: () => failure),
        );
    }
  }

  /// Keeps the current list on screen. Returns when done, so it can back a
  /// `RefreshIndicator.onRefresh`.
  Future<void> refresh() async {
    if (state.orders.isEmpty) return load();
    if (state.isRefreshing) return;
    final generation = ++_generation;
    safeEmit(
      state.copyWith(
        isRefreshing: true,
        isLoadingMore: false,
        failure: () => null,
      ),
    );
    final result = await _repository.fetchOrders(page: 1);
    if (generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        safeEmit(_firstPage(value));
      case Err(:final failure):
        _report(failure);
        safeEmit(state.copyWith(isRefreshing: false, failure: () => failure));
    }
  }

  Future<void> loadMore() async {
    final page = state.nextPage;
    if (state.status != OrdersStatus.success ||
        state.isRefreshing ||
        state.isLoadingMore ||
        page == null) {
      return;
    }
    final generation = _generation;
    safeEmit(state.copyWith(isLoadingMore: true, failure: () => null));
    final result = await _repository.fetchOrders(page: page);
    // A refresh started meanwhile: this page continues the old list.
    if (generation != _generation) return;
    switch (result) {
      case Ok(:final value):
        safeEmit(
          state.copyWith(
            orders: [...state.orders, ...value],
            nextPage: () => value.isEmpty ? null : page + 1,
            isLoadingMore: false,
          ),
        );
      case Err(:final failure):
        _report(failure);
        safeEmit(state.copyWith(isLoadingMore: false, failure: () => failure));
    }
  }

  OrdersState _firstPage(List<Order> orders) => OrdersState(
    status: OrdersStatus.success,
    orders: orders,
    nextPage: orders.isEmpty ? null : 2,
  );

  /// A bug, not a network condition: hand it to `onError`, which a
  /// `BlocObserver` forwards to the crash reporter.
  void _report(AppFailure failure) {
    if (failure is UnexpectedFailure) {
      addError(failure.error, failure.stackTrace);
    }
  }
}
