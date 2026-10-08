// Target: lib/features/orders/presentation/widgets/orders_effects_listener.dart
import 'package:app/core/bloc/action_status.dart';
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/ui/show_failure.dart';
import 'package:app/features/orders/presentation/cubit/place_order_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Every one-shot effect of the checkout screen in one place. Wrap the view
/// with it inside the page, below the providers and below the router.
class OrdersEffectsListener extends StatelessWidget {
  const OrdersEffectsListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<PlaceOrderCubit, ActionStatus>(
          // Fires once per transition into success, not on every rebuild.
          listenWhen: (previous, next) =>
              previous is! ActionSucceeded<String> &&
              next is ActionSucceeded<String>,
          listener: (context, status) {
            final orderId = (status as ActionSucceeded<String>).value;
            // Pass the id; the destination loads the order itself.
            context.go('/orders/$orderId');
          },
        ),
        BlocListener<PlaceOrderCubit, ActionStatus>(
          listenWhen: (previous, next) =>
              next is ActionFailed && previous != next,
          listener: (context, status) {
            final failure = (status as ActionFailed).failure;
            showFailure(context, failure);
            if (failure is OutcomeUnknownFailure) {
              // The order may exist. Never offer a blind retry: send the user
              // to the list, which reads the real outcome from the server.
              context.go('/orders');
            }
          },
        ),
      ],
      child: child,
    );
  }
}
