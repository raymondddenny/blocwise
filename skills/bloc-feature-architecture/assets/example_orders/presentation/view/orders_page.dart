// Target: lib/features/orders/presentation/view/orders_page.dart
import 'package:app/core/di/injector.dart';
import 'package:app/features/orders/presentation/cubit/orders_cubit.dart';
import 'package:app/features/orders/presentation/view/orders_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Owns the providers. The only place in the feature that calls `sl`.
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<OrdersCubit>()..load(),
      child: const OrdersView(),
    );
  }
}
