// Target: lib/features/orders/presentation/view/orders_view.dart
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/failures/failure_copy.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:app/features/orders/presentation/cubit/orders_cubit.dart';
import 'package:app/features/orders/presentation/cubit/orders_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class OrdersView extends StatelessWidget {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: BlocBuilder<OrdersCubit, OrdersState>(
        builder: (context, state) => switch (state.status) {
          OrdersStatus.initial || OrdersStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          OrdersStatus.failure => _FailureBody(failure: state.failure),
          OrdersStatus.success => _OrdersList(state: state),
        },
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.state});

  final OrdersState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OrdersCubit>();
    final failure = state.failure;
    return RefreshIndicator(
      onRefresh: cubit.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // loadMore guards itself, so calling it on every scroll is safe.
          if (notification.metrics.extentAfter < 300) cubit.loadMore();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (failure != null)
              ListTile(title: Text(context.read<FailureCopy>().of(failure))),
            for (final order in state.orders) _OrderTile(order: order),
            if (state.isLoadingMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(order.id),
      subtitle: Text(switch (order.status) {
        OrderStatus.paid => 'Paid',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.pending || OrderStatus.unknown => 'Processing',
      }),
      // Use intl's NumberFormat.simpleCurrency with the current locale in an
      // app; toStringAsFixed keeps this example dependency-free.
      trailing: Text((order.totalCents / 100).toStringAsFixed(2)),
    );
  }
}

class _FailureBody extends StatelessWidget {
  const _FailureBody({required this.failure});

  final AppFailure? failure;

  @override
  Widget build(BuildContext context) {
    final failure = this.failure;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failure != null) Text(context.read<FailureCopy>().of(failure)),
          TextButton(
            onPressed: () => context.read<OrdersCubit>().load(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
