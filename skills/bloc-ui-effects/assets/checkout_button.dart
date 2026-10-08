// Target: lib/features/orders/presentation/widgets/checkout_button.dart
import 'package:app/core/bloc/action_status.dart';
import 'package:app/features/orders/domain/order.dart';
import 'package:app/features/orders/presentation/cubit/place_order_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Places [draft] through the `PlaceOrderCubit` above it. The effects
/// listener, not this button, reacts to the outcome.
class CheckoutButton extends StatelessWidget {
  const CheckoutButton({required this.draft, required this.label, super.key});

  final OrderDraft draft;
  final String label;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaceOrderCubit, ActionStatus>(
      buildWhen: (previous, next) =>
          (previous is ActionRunning) != (next is ActionRunning),
      builder: (context, status) {
        final running = status is ActionRunning;
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: running
                ? null
                : () {
                    // Read the cubit at tap time; `status` above is the
                    // snapshot from the last rebuild, not the live state.
                    final cubit = context.read<PlaceOrderCubit>();
                    if (cubit.state is ActionRunning) return;
                    cubit.place(draft);
                  },
            child: running
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        );
      },
    );
  }
}
