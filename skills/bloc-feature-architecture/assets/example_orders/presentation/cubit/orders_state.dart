// Target: lib/features/orders/presentation/cubit/orders_state.dart
import 'package:app/core/failures/app_failure.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum OrdersStatus { initial, loading, success, failure }

/// One state with a status enum: the list stays visible while refreshing or
/// loading more, which a sealed state per phase would have to copy around.
final class OrdersState extends Equatable {
  const OrdersState({
    this.status = OrdersStatus.initial,
    this.orders = const [],
    this.nextPage,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.failure,
  });

  final OrdersStatus status;
  final List<Order> orders;

  /// The page [OrdersCubit.loadMore] fetches next; null when the last page
  /// came back empty.
  final int? nextPage;
  final bool isRefreshing;
  final bool isLoadingMore;

  /// The last failure. With [orders] empty the view renders it full screen;
  /// with data on screen it shows a line above the list.
  final AppFailure? failure;

  bool get hasMore => nextPage != null;

  /// Nullable fields take a [ValueGetter] so `() => null` can clear them;
  /// a plain `int?` parameter cannot tell "clear" from "leave as is".
  OrdersState copyWith({
    OrdersStatus? status,
    List<Order>? orders,
    ValueGetter<int?>? nextPage,
    bool? isRefreshing,
    bool? isLoadingMore,
    ValueGetter<AppFailure?>? failure,
  }) {
    return OrdersState(
      status: status ?? this.status,
      orders: orders ?? this.orders,
      nextPage: nextPage != null ? nextPage() : this.nextPage,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      failure: failure != null ? failure() : this.failure,
    );
  }

  @override
  List<Object?> get props => [
    status,
    orders,
    nextPage,
    isRefreshing,
    isLoadingMore,
    failure,
  ];
}
